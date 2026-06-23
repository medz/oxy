import 'dart:async';

import 'package:oxy/oxy.dart';

import 'src/data.dart';
import 'src/runner.dart';

final oxySuite = BenchmarkSuite('oxy', <BenchmarkCase>[
  SyncBenchmark(
    group: 'request',
    name: 'construct-get',
    run: () {
      consume(Request('/users/42', headers: headerPairs8));
    },
  ),
  SyncBenchmark(
    group: 'request',
    name: 'copy-with-headers',
    run: () {
      consume(_request.copyWith(headers: headerPairs32));
    },
  ),
  SyncBenchmark(
    group: 'body',
    name: 'construct-string',
    run: () {
      consume(Body(jsonText));
    },
  ),
  SyncBenchmark(
    group: 'body',
    name: 'clone-bytes',
    run: () {
      consume(Body(largeBytes).clone());
    },
  ),
  AsyncBenchmark(
    group: 'body',
    name: 'bytes-1k',
    run: () async {
      consume(await Body(smallBytes).bytes());
    },
  ),
  AsyncBenchmark(
    group: 'response',
    name: 'bytes-1k',
    run: () async {
      consume(await Response.bytes(smallBytes).bytes());
    },
  ),
  AsyncBenchmark(
    group: 'response',
    name: 'json-decode',
    run: () async {
      consume(await Response.json(jsonPayload).json<Map<String, Object?>>());
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'send-no-middleware',
    run: () async {
      consume(await _plainClient.send(_request));
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'request-json-body',
    run: () async {
      consume(await _plainClient.post('/users', json: jsonPayload));
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'send-5-middleware',
    run: () async {
      consume(await _middlewareClient.send(_request));
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'retry-replayable-body',
    run: () async {
      consume(await _retryClient.send(_putRequest));
    },
  ),
]);

final _request = Request(
  '/users/42',
  headers: headerPairs8,
  options: const RequestOptions(query: <String, Object?>{'include': 'profile'}),
);

final _putRequest = Request(
  '/users/42',
  method: 'PUT',
  headers: const <String, String>{'content-type': 'application/octet-stream'},
  body: Body(largeBytes),
);

final _plainClient = Client(
  ClientOptions(
    baseUrl: Uri.parse('https://example.test'),
    transport: const _StaticTransport(),
  ),
);

final _middlewareClient = Client(
  ClientOptions(
    baseUrl: Uri.parse('https://example.test'),
    transport: const _StaticTransport(),
    middleware: List<Middleware>.filled(5, const _NoopMiddleware()),
  ),
);

final _retryClient = Client(
  ClientOptions(
    baseUrl: Uri.parse('https://example.test'),
    transport: const _RetryTransport(),
    retryPolicy: const RetryPolicy(
      maxRetries: 2,
      idempotentMethodsOnly: false,
      baseDelay: Duration.zero,
      maxDelay: Duration.zero,
      jitterRatio: 0,
    ),
  ),
);

final class _StaticTransport implements Transport {
  const _StaticTransport();

  @override
  PlatformCapability get capability => PlatformCapability.test;

  @override
  Future<void> close() => Future<void>.value();

  @override
  Future<Response> send(Request request, Context context) {
    return Future<Response>.value(Response.bytes(const <int>[]));
  }
}

final class _RetryTransport implements Transport {
  const _RetryTransport();

  @override
  PlatformCapability get capability => PlatformCapability.test;

  @override
  Future<void> close() => Future<void>.value();

  @override
  Future<Response> send(Request request, Context context) {
    final status = context.attempt < 2 ? 503 : 200;
    return Future<Response>.value(
      Response.bytes(const <int>[], status: status),
    );
  }
}

final class _NoopMiddleware
    implements
        RequestTransformer,
        AttemptTransformer,
        AttemptResponseHandler,
        FinalResponseHandler,
        FinalFinallyHandler {
  const _NoopMiddleware();

  @override
  Request onRequest(Request request, Context context) => request;

  @override
  Request onAttempt(Request request, Context context) => request;

  @override
  Response onAttemptResponse(
    Request request,
    Response response,
    Context context,
  ) {
    return response;
  }

  @override
  Response onResponse(Request request, Response response, Context context) {
    return response;
  }

  @override
  void onFinally(Request request, Context context) {}
}
