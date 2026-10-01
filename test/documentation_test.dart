@TestOn('vm')
library;

import 'dart:io' as io;
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  for (final path in ['README.md', 'doc/cookbook.md']) {
    test('$path policy example resolves its relative URL', () async {
      final blocks = RegExp(r'```dart\n([\s\S]*?)```')
          .allMatches(await io.File(path).readAsString())
          .map((match) => match.group(1)!)
          .toList();
      var configuration = blocks.singleWhere(
        (block) =>
            block.contains('final client = Client(') &&
            block.contains('redirectPolicy: RedirectPolicy.manual'),
      );
      var request = blocks.singleWhere(
        (block) =>
            block.contains("'/missing'") &&
            block.contains('StatusPolicy.returnResponse'),
      );
      if (configuration == request) {
        final requestStart = configuration.indexOf('final response =');
        request = configuration.substring(requestStart);
        configuration = configuration.substring(0, requestStart);
      }
      final directory = await io.Directory.systemTemp.createTemp('oxy-doc-');
      addTearDown(() => directory.delete(recursive: true));
      final script = io.File('${directory.path}/policy.dart');
      // Only replace the socket transport; execute the published configuration
      // and request verbatim so URL and per-request policy mistakes are visible.
      final withTransport = configuration.replaceFirst(
        'ClientOptions(',
        'ClientOptions(transport: MockTransport((_, _) async => '
            'Response.text("missing", status: 404)),',
      );
      await script.writeAsString('''
import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';
Future<void> main() async {
  $withTransport
  try {
    $request
    if (response.status != 404) throw StateError('Expected returned 404');
    if (await response.text() != 'missing') throw StateError('Expected body');
  } finally {
    await client.close();
  }
}
''');
      final packageConfig = (await Isolate.packageConfig)!.toFilePath();
      final result = await io.Process.run(io.Platform.resolvedExecutable, [
        '--packages=$packageConfig',
        script.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  }
}
