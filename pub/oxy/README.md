# Oxy

`oxy` is a fetch-style HTTP client for Dart/Flutter built on top of [`ht`](https://pub.dev/packages/ht).

[![Oxy Test](https://github.com/medz/oxy/actions/workflows/oxy-test.yml/badge.svg)](https://github.com/medz/oxy/actions/workflows/oxy-test.yml)
[![Oxy Version](https://img.shields.io/pub/v/oxy)](https://pub.dev/packages/oxy)

## Why Oxy

- Uses `ht` as the unified HTTP type layer (`Request`, `Response`, `Headers`, `FormData`, `Blob`, ...)
- No adapter abstraction
- Works on Dart VM and Web with one API
- Includes request timeout, redirect policy, keep-alive, and abort signal support

## Installation

```yaml
dependencies:
  oxy: ^0.1.0
```

## Quick Start

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Oxy(baseURL: Uri.parse('https://httpbin.org'));

  final response = await client.post(
    '/post',
    json: {'name': 'oxy'},
  );

  final data = await response.json<Map<String, dynamic>>();
  print(data['json']);
}
```

## Use `ht` Types Directly

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final request = Request(
    Uri.parse('https://httpbin.org/get'),
    headers: Headers({'x-from': 'oxy'}),
  );

  final response = await oxy(request);
  print(response.status);
}
```

## Redirect / Timeout / Abort

```dart
import 'dart:async';

import 'package:oxy/oxy.dart';

Future<void> main() async {
  final signal = AbortSignal();
  Timer(const Duration(milliseconds: 200), () => signal.abort('cancelled'));

  await oxy.get(
    'https://httpbin.org/delay/3',
    options: const FetchOptions(
      timeout: Duration(seconds: 1),
      redirect: RedirectPolicy.follow,
      keepAlive: true,
    ).copyWith(signal: signal),
  );
}
```

## License

MIT
