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

`OxyResult` also provides helpers: `fold(...)`, `map(...)`, `getOrThrow()`.

## HTTP Error Policy

By default, non-2xx responses throw `OxyHttpException`.
Use `HttpErrorPolicy.returnResponse` when you want to handle status codes manually:

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Oxy(
    OxyConfig(baseUrl: Uri.parse('https://api.example.com')),
  );

  final response = await client.get(
    '/users/404',
    options: const RequestOptions(
      httpErrorPolicy: HttpErrorPolicy.returnResponse,
    ),
  );

  if (response.status == 404) {
    // handle as regular response
  }
}
```

## Middleware Composition

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Oxy(
    OxyConfig(
      baseUrl: Uri.parse('https://api.example.com'),
      middleware: <OxyMiddleware>[
        RequestIdMiddleware(),
        AuthMiddleware.staticToken('token'),
        CookieMiddleware(MemoryCookieJar()),
        CacheMiddleware(store: MemoryCacheStore()),
        LoggingMiddleware(),
      ],
    ),
  );

  await client.get('/feed');
}
```

## Presets

`oxy` provides three official presets for different complexity levels:

- `OxyPresets.minimal(...)`: `RequestId` only
- `OxyPresets.standard(...)`: `RequestId + Cache + Logging` by default, optional `Auth/Cookie`
- `OxyPresets.full(...)`: `RequestId + Cookie + Cache + Logging`, optional `Auth`

Use the `standard` preset for most projects:

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Oxy(
    OxyConfig(
      baseUrl: Uri.parse('https://api.example.com'),
      middleware: OxyPresets.standard(
        authMiddleware: AuthMiddleware.staticToken('token'),
        cookieJar: MemoryCookieJar(),
      ),
    ),
  );

  await client.get('/feed');
}
```

You can also toggle built-ins or override middlewares:

```dart
final middleware = OxyPresets.standard(
  includeLogging: false,
  cacheMiddleware: CacheMiddleware(store: MemoryCacheStore()),
);
```

Or apply presets via fluent helpers:

```dart
final client = Oxy()
    .withStandardPreset(includeLogging: false)
    .withPreset([AuthMiddleware.staticToken('token')]);
```

Choose a lower or higher preset as needed:

```dart
final minimalClient = Oxy().withMinimalPreset();

final fullClient = Oxy().withFullPreset(
  authMiddleware: AuthMiddleware.staticToken('token'),
);
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
