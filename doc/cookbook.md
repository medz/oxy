# Oxy Cookbook

This cookbook shows the common paths that are useful when Oxy sits inside an
application or reusable API client. The examples are also available as Dart
files under `example/`, so `dart analyze` checks that they keep compiling.

## Build a Reusable API Client

Create one long-lived `Client` with a base URL and policies, then hide it behind
small domain methods. Decode at the edge of that client instead of spreading
JSON casts across the app.

See [`example/api_client.dart`](../example/api_client.dart).

```dart
final client = Client(
  ClientOptions(
    baseUrl: Uri.parse('https://api.example.com'),
    timeoutPolicy: const TimeoutPolicy(total: Duration(seconds: 10)),
    retryPolicy: const RetryPolicy(maxRetries: 2),
  ),
);

final user = await client.decode<User>(
  'GET',
  '/users/42',
  decoder: User.fromJson,
);
```

Close clients that own their transport:

```dart
try {
  // use the client
} finally {
  await client.close();
}
```

## Configure Policies Per Client or Request

Client options define the normal behavior. `RequestOptions` can override that
behavior for one call.

See [`example/policies.dart`](../example/policies.dart).

```dart
final client = Client(
  ClientOptions(
    timeoutPolicy: const TimeoutPolicy(total: Duration(seconds: 20)),
    retryPolicy: const RetryPolicy(maxRetries: 1),
    redirectPolicy: RedirectPolicy.manual,
  ),
);

final response = await client.get(
  '/missing',
  options: const RequestOptions(statusPolicy: StatusPolicy.returnResponse),
);
```

Use `StatusPolicy.returnResponse` when non-2xx responses are expected data. Keep
the default `StatusPolicy.throwOnError` when non-2xx responses should fail fast
with `StatusError`.

## Use Result for No-Throw Flows

Use `Result` when a caller should branch on success or failure without a
`try`/`catch`.

See [`example/no_throw_result.dart`](../example/no_throw_result.dart).

```dart
final result = await client.requestResult('GET', '/health');

final message = result.fold(
  onSuccess: (response) => 'status ${response.status}',
  onFailure: (error, trace) => 'failed with $error',
);
```

`Result.getOrThrow()` restores the exception path when a later layer wants to
rethrow the captured failure with its original stack trace.

## Compose Middleware

Configure middleware as one list. Each middleware declares the lifecycle
capabilities it needs, and Oxy schedules those capabilities at the request,
attempt, or final response phase.

See [`example/middleware_stack.dart`](../example/middleware_stack.dart).

```dart
final client = Client(
  ClientOptions(
    middleware: [
      RequestIdMiddleware(),
      AuthMiddleware.staticToken('secret'),
      CookieMiddleware(MemoryCookieJar()),
      CacheMiddleware(),
      LoggingMiddleware(),
    ],
  ),
);
```

`CookieMiddleware` works from the main middleware list and stores cookies across
redirects and retries. It is for native and test transports. Browser requests
already use browser cookie handling, so the middleware is a no-op on Web.

Custom middleware implements the capabilities it needs:

```dart
final class TraceMiddleware
    implements RequestTransformer, FinalResponseHandler {
  @override
  Request onRequest(Request request, Context context) {
    return request.withHeader('x-trace-id', 'trace-1');
  }

  @override
  Response onResponse(Request request, Response response, Context context) {
    return response;
  }
}
```

## Test with MockTransport

`MockTransport` lets tests exercise the real `Client` pipeline without opening a
socket.

```dart
final transport = MockTransport((request, context) async {
  if (request.headers.get('authorization') != 'Bearer secret') {
    throw StateError('missing authorization');
  }
  return Response.json({'ok': true});
});

final client = Client(ClientOptions(transport: transport));
```

`transport.requests` records the prepared requests, which is useful for checking
headers, URLs, methods, and body behavior.

## Handle Body Replayability

Oxy tracks whether request and response bodies are replayable.

- `String`, `List<int>`, `Uint8List`, JSON bodies, `Blob`, `FormData`, and
  `URLSearchParams` are replayable.
- Raw `Stream<List<int>>` bodies are one-shot.
- One-shot request bodies are not retried implicitly.
- Use `Response.buffered()` when later code needs to read a streaming response
  body more than once.

```dart
final response = await client.get('/report');
final buffered = await response.buffered(maxBytes: 1024 * 1024);

print(await buffered.text());
print(await buffered.text());
```
