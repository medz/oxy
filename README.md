# Oxy

`oxy` is a fetch-style HTTP client for Dart/Flutter, built on top of [`ht`](https://pub.dev/packages/ht).

[![Oxy Test](https://github.com/medz/oxy/actions/workflows/oxy-test.yml/badge.svg)](https://github.com/medz/oxy/actions/workflows/oxy-test.yml)
[![Oxy Version](https://img.shields.io/pub/v/oxy)](https://pub.dev/packages/oxy)

## Why Oxy

- Unified `ht` type layer (`Request`, `Response`, `Headers`, `FormData`, `Blob`, ...)
- No adapter abstraction
- One API for Dart VM and Web
- Two usage layers: simple `get/post/...` and advanced `request/send`
- Middleware-first extensibility (auth, cookies, cache, logging, trace)
- Built-in retry/timeout/abort/error model with `throw` and `safe*` APIs

## Installation

```yaml
dependencies:
  oxy: ^0.1.0
```

## Quick Start

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Oxy(
    OxyConfig(baseUrl: Uri.parse('https://httpbin.org')),
  );

  final response = await client.post(
    '/post',
    json: {'name': 'oxy'},
  );

  final payload = await response.decode<Map<String, Object?>>();
  print(payload['json']);
}
```

## Safe API (No Throw)

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Oxy(
    OxyConfig(baseUrl: Uri.parse('https://api.example.com')),
  );

  final result = await client.safeGetDecoded<bool>(
    '/health',
    decoder: (value) => (value as Map<String, Object?>)['ok'] as bool,
  );

  if (result.isFailure) {
    print('request failed: ${result.error}');
    return;
  }

  print('healthy: ${result.value}');
}
```

## Middleware Composition

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Oxy(
    OxyConfig(
      baseUrl: Uri.parse('https://api.example.com'),
      cookieJar: MemoryCookieJar(),
      middleware: <OxyMiddleware>[
        RequestIdMiddleware(),
        AuthMiddleware.staticToken('token'),
        CacheMiddleware(store: MemoryCacheStore()),
        LoggingMiddleware(),
      ],
    ),
  );

  await client.get('/feed');
}
```

## Advanced `Request/send` API

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Oxy();

  final request = Request(
    Uri.parse('https://httpbin.org/get'),
    headers: Headers({'x-from': 'oxy'}),
  );

  final response = await client.send(
    request,
    options: const RequestOptions(
      requestTimeout: Duration(seconds: 5),
      retryPolicy: RetryPolicy(maxRetries: 2),
    ),
  );

  print(response.status);
}
```

## Top-level Helpers

Use the global client helpers for quick scripts:

- `fetch(...)`
- `safeFetch(...)`
- `fetchDecoded<T>(...)`
- `safeFetchDecoded<T>(...)`

## License

MIT
