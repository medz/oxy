# Oxy

`oxy` is a modern HTTP client for Dart and Flutter. It is built around a small
core model: `Client`, `Request`, `Response`, `Headers`, `Body`, policies,
middleware, and typed request errors.

[![CI](https://github.com/medz/oxy/actions/workflows/ci.yml/badge.svg)](https://github.com/medz/oxy/actions/workflows/ci.yml)
[![Oxy Version](https://img.shields.io/pub/v/oxy)](https://pub.dev/packages/oxy)

## Design Goals

- One package, no adapter-package split.
- Core public types use semantic names: `Client`, `Request`, `Response`.
- Native and Web transports are built into Oxy.
- Reusable clients are the production path and keep connections alive by default.
- Retry, timeout, redirect, status validation, and decoding are explicit policies.
- `Result.capture(...)`, `sendResult(...)`, and `fetchResult(...)` provide no-throw flows without multiplying every HTTP method.
- Request bodies carry replayability metadata, so one-shot streams are not retried accidentally.
- Middleware runs through a clear pipeline: application middleware once per logical request, network middleware once per attempt.

## Installation

```yaml
dependencies:
  oxy: ^0.3.0
```

## Quick Start

```dart
import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Client(
    ClientOptions(baseUrl: Uri.parse('https://httpbin.org')),
  );

  try {
    final response = await client.post('/post', json: {'name': 'oxy'});
    final payload = await response.json<Map<String, Object?>>();
    print(payload['json']);
  } finally {
    await client.close();
  }
}
```

## Result API

```dart
final result = await Result.capture(() {
  return client.get('/health');
});

if (result.isFailure) {
  print(result.error);
  return;
}

print(result.value!.status);
```

You can also use `client.sendResult(...)`, `client.requestResult(...)`, or
top-level `fetchResult(...)`.

## Status Policy

By default Oxy throws `StatusError` for non-2xx responses. Disable validation
when status codes are part of the expected control flow:

```dart
final response = await client.get(
  '/users/404',
  options: const RequestOptions(statusPolicy: StatusPolicy.returnResponse),
);
```

## Middleware

Application middleware runs once for the logical request. Network middleware
runs once for every network attempt, including retries.

```dart
final client = Client(
  ClientOptions(
    baseUrl: Uri.parse('https://api.example.com'),
    middleware: [
      RequestIdMiddleware(),
      AuthMiddleware.staticToken('token'),
    ],
    networkMiddleware: [
      CookieMiddleware(MemoryCookieJar()),
      LoggingMiddleware(),
    ],
  ),
);
```

## Policies

```dart
final client = Client(
  ClientOptions(
    timeoutPolicy: const TimeoutPolicy(total: Duration(seconds: 20)),
    retryPolicy: const RetryPolicy(maxRetries: 2),
    redirectPolicy: RedirectPolicy.follow,
    statusPolicy: StatusPolicy.throwOnError,
  ),
);
```

Retry is conservative by default: idempotent methods only, retryable network
errors/timeouts, selected transient status codes, jittered backoff, and no
retries for non-replayable request bodies.

## Request Bodies

Oxy owns its public `Client`, `Request`, and `Response` model, but it reuses
mature body helpers from `ht` for form construction. These helpers are exported
selectively; `ht.Request` and `ht.Response` are not part of Oxy's public API.

```dart
final form = FormData()
  ..append('name', const Multipart.text('oxy'))
  ..append('file', Multipart.blob(Blob(['hello'], 'text/plain'), 'hello.txt'));

await client.post('/upload', body: form);
```

`String`, `List<int>`, `Uint8List`, `Stream<List<int>>`, `Blob`, `FormData`,
and `URLSearchParams` are accepted as body inputs. Replayable bodies can be
retried safely; one-shot streams are never retried implicitly.

## Testing

Use the in-package test transport for deterministic client tests:

```dart
import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';

final transport = MockTransport((request, context) async {
  return Response.json({'ok': true});
});

final client = Client(ClientOptions(transport: transport));
```

## License

MIT
