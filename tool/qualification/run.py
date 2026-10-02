"""Run public-API Flutter applications against an observable loopback server."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import time
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--platforms', default='macos,web')
    dependency = parser.add_mutually_exclusive_group(required=True)
    dependency.add_argument('--oxy-version')
    dependency.add_argument('--oxy-source', type=Path)
    parser.add_argument('--chrome-binary', type=Path)
    parser.add_argument('--chromedriver', type=Path)
    parser.add_argument('--step-timeout', type=float, default=900,
                        help='Maximum seconds per Flutter step (default: 900)')
    args = parser.parse_args()
    if args.step_timeout <= 0:
        parser.error('--step-timeout must be positive')
    workspace = args.workspace.resolve()
    workspace.mkdir(parents=True, exist_ok=False)
    app = workspace / 'consumer'
    logs = workspace / 'logs'
    logs.mkdir()
    fixture = Path(__file__).resolve().parent
    flutter_binary = args.flutter.resolve()
    dart = flutter_binary.parent / 'cache/dart-sdk/bin/dart'
    env = os.environ.copy()
    env.update(PUB_CACHE=str(workspace / 'pub-cache'),
               XDG_CONFIG_HOME=str(workspace / 'config'),
               FLUTTER_SUPPRESS_ANALYTICS='true', CI='true',
               CLANG_MODULE_CACHE_PATH=str(workspace / 'clang-cache'),
               SWIFT_MODULE_CACHE_PATH=str(workspace / 'swift-cache'))
    flutter = [str(flutter_binary), '--suppress-analytics', '--no-version-check']

    def run(name, command, cwd=app):
        with (logs / f'{name}.log').open('w') as output:
            with subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                  stderr=subprocess.STDOUT,
                                  start_new_session=True) as process:
                try:
                    code = process.wait(timeout=args.step_timeout)
                except subprocess.TimeoutExpired:
                    output.write(f'\n{name}: timed out after {args.step_timeout}s\n')
                    output.flush()
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        pass
                    # The wrapper can exit before its compiler/browser children.
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
                    code = 124
        print(f'{name}: exit {code}', flush=True)
        return code

    platforms = args.platforms.split(',')
    if not set(platforms) <= {'macos', 'web'}:
        parser.error('--platforms must contain macos and/or web')
    if 'web' in platforms and not (args.chrome_binary and args.chromedriver):
        parser.error('Web needs a matched --chrome-binary and --chromedriver')
    if run('create', flutter + ['create', '--project-name=oxy_consumer',
                               '--platforms=' + args.platforms, '--no-pub',
                               str(app)], cwd=workspace):
        return 1
    for template in (fixture / 'flutter').rglob('*.template'):
        target = app / template.relative_to(fixture / 'flutter').with_suffix('')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(template, target)
    if args.oxy_source:
        oxy = '    path: ' + json.dumps(str(args.oxy_source.resolve()))
    else:
        oxy = '    version: ' + json.dumps(args.oxy_version)
    (app / 'pubspec.yaml').write_text('name: oxy_consumer\npublish_to: none\n'
        'environment:\n  sdk: ^3.12.0\ndependencies:\n'
        '  flutter:\n    sdk: flutter\n  oxy:\n' + oxy + '\n'
        'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n'
        '  integration_test:\n    sdk: flutter\n')
    (app / 'analysis_options.yaml').write_text('analyzer:\n  exclude:\n    - build/**\n')
    shutil.rmtree(app / 'test')
    if 'macos' in platforms:
        for name in ['DebugProfile', 'Release']:
            path = app / f'macos/Runner/{name}.entitlements'
            path.write_text(path.read_text().replace('</dict>',
                '<key>com.apple.security.network.client</key>\n<true/>\n</dict>'))
    if run('pub-get', flutter + ['pub', 'get']):
        return 1
    shutil.copy2(app / 'pubspec.lock', logs / 'pubspec.lock')
    shutil.copy2(app / '.dart_tool/package_config.json', logs / 'package_config.json')
    if run('analyze', flutter + ['analyze']):
        return 1

    server_output = (logs / 'wire-server.log').open('w')
    driver_output = (logs / 'chromedriver.log').open('w')
    server = subprocess.Popen([str(dart), str(fixture / 'server.dart')], env=env,
                              stdout=server_output, stderr=subprocess.STDOUT)
    driver = None
    outcomes = {}
    try:
        deadline = time.monotonic() + 20
        base_url = None
        while time.monotonic() < deadline:
            for line in (logs / 'wire-server.log').read_text().splitlines():
                if line.startswith('BASE_URL='):
                    base_url = line.split('=', 1)[1]
            if base_url or server.poll() is not None:
                break
            time.sleep(0.1)
        if not base_url:
            raise RuntimeError('Loopback server did not start; inspect wire-server.log')
        defines = ['--dart-define=QUALIFICATION_BASE_URL=' + base_url]
        if 'macos' in platforms:
            outcomes['macos'] = run('macos', flutter + ['test',
                'integration_test/transport_test.dart', '-d', 'macos',
                '--reporter=expanded', *defines,
                '--dart-define=QUALIFICATION_RUN=macos'])
        if 'web' in platforms:
            with socket.socket() as connection:
                connection.bind(('127.0.0.1', 0))
                port = connection.getsockname()[1]
            driver = subprocess.Popen([str(args.chromedriver.resolve()),
                '--port=' + str(port)], env=env, stdout=driver_output,
                stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                try:
                    urllib.request.urlopen(f'http://127.0.0.1:{port}/status',
                                           timeout=1).close()
                    break
                except OSError:
                    time.sleep(0.1)
            else:
                raise RuntimeError('ChromeDriver did not start')
            outcomes['web'] = run('web', flutter + ['drive',
                '--driver=test_driver/integration_test.dart',
                '--target=integration_test/transport_test.dart', '-d', 'web-server',
                '--headless', '--driver-port=' + str(port),
                '--chrome-binary=' + str(args.chrome_binary.resolve()), *defines,
                '--dart-define=QUALIFICATION_RUN=web'])
        (logs / 'outcomes.json').write_text(json.dumps(outcomes, indent=2) + '\n')
        shutil.copy2(app / '.dart_tool/package_config.json',
                     logs / 'package_config-after-build.json')
        return int(any(outcomes.values()))
    finally:
        for process in [driver, server]:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        server_output.close()
        driver_output.close()


if __name__ == '__main__':
    raise SystemExit(main())
