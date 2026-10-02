# Application qualification

These fixtures import only Oxy's public API and run as real Flutter
applications, using `integration_test` on macOS and Chrome. They complement
the VM/Node/Chrome Dart suites. They do not use `MockTransport` or Flutter's
widget-test HTTP override.

The raw loopback HTTP server holds chunked responses open and records when the
client closes each socket. Tests require that closure after read/total timeout,
caller abort, and cancellation of a pending response read, then reuse the
client. They also check Unicode JSON POST, 128KiB payload integrity, response
buffering, capability metadata, and automatic RFC850 dependency overlays.

## Run

Use Python 3, a Flutter SDK, Xcode for macOS, and a matched Chrome/ChromeDriver
pair for Web. The workflow pins Flutter 3.47.5 and Chrome/ChromeDriver
150.0.7871.115. Local qualification also uses Dart 3.13.4 and Xcode 27.0.
This establishes those specific targets, not all Flutter versions or devices.

Provide a new, disposable workspace outside the repository. The runner creates
the app, pub cache, logs, and build caches there, and stops its server/driver
when finished. It never deletes an existing workspace. Flutter can also write
its SDK cache, so provide an isolated SDK if sharing a developer installation.
Analytics are suppressed for the run. No login is required.
Each Flutter step has a 900-second timeout, configurable with `--step-timeout`.
A timed-out step logs its name, returns code 124, and stops its process group;
the runner also stops its owned server/driver on exit.

The cold macOS automatic-overlay probe is currently a known failing admission
gate: the first compiled app uses the original `http_parser` even though the
build hook has updated package resolution by the end of the build. The runner
retains that failure and exits nonzero; passing transport tests do not imply
that this separate gate passed. Web and ordinary Dart consumers are qualified
independently. Do not warm/retry the app and call that a cold-build pass.

```sh
python3 tool/qualification/run.py \
  --flutter /path/to/isolated/flutter/bin/flutter \
  --workspace /path/to/new/qualification-workspace \
  --oxy-source "$PWD" \
  --chrome-binary /path/to/chrome \
  --chromedriver /path/to/chromedriver
```

Use `--platforms web` or `--platforms macos` to run one target. With macOS only,
omit Chrome/ChromeDriver arguments. To verify an immutable hosted package,
replace `--oxy-source "$PWD"` with `--oxy-version 0.7.1`. The published 0.7.1
baseline fails pending-body cancellation on Web and with the default total
timeout on macOS; the source candidate must pass.

Inspect `logs/outcomes.json`, platform logs, `wire-server.log`, the resolved
lockfile, and package configurations before/after the build. A source run does
not count as hosted artifact qualification. Hosted runs use ordinary pub
resolution with no manual overlay or dependency override.

## Scope

The UI assertion proves the Flutter app and engine run; network and server
observations establish transport behavior. This is not a visual UI audit.
macOS needs the generated application's network-client entitlement, which the
runner adds to both generated build configurations.

Android, iOS, Windows, Linux native apps, release-mode builds, and browser
HTTP/2 streaming uploads remain separate qualification targets. The loopback
fixture uses HTTP/1.1 and buffered uploads; the Web test does not promise
streaming uploads to HTTP/1.1 servers.
