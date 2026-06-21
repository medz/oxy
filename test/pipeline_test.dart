import 'dart:async';

import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';
import 'package:test/test.dart';

final class CapabilityTransport implements Transport {
  CapabilityTransport(this.capability, this._responder);

  @override
  final PlatformCapability capability;

  final Future<Response> Function(Request request, Context context) _responder;

  @override
  Future<void> close() async {}

  @override
  Future<Response> send(Request request, Context context) {
    return _responder(request, context);
  }
}

final class RequestHeaderMiddleware implements RequestTransformer {
  RequestHeaderMiddleware(this.name, this.value, this.events);

  final String name;
  final String value;
  final List<String> events;

  @override
  Request onRequest(Request request, Context context) {
    events.add('$name:${context.attempt}');
    return request.withHeader(name, value);
  }
}

final class AttemptHeaderMiddleware implements AttemptTransformer {
  AttemptHeaderMiddleware(this.name, this.value, this.events);

  final String name;
  final String value;
  final List<String> events;

  @override
  Request onAttempt(Request request, Context context) {
    events.add('$name:${context.attempt}');
    return request.withHeader(name, value);
  }
}

final class PassThroughMiddleware implements RequestTransformer {
  const PassThroughMiddleware();

  @override
  Request onRequest(Request request, Context context) => request;
}

final class ShortCircuitMiddleware implements RequestResolver {
  const ShortCircuitMiddleware(this.response);

  final Response response;

  @override
  Response resolve(Request request, Context context) => response;
}

void main() {
  test(
    'schedules request middleware once and attempt middleware per attempt',
    () async {
      var calls = 0;
      final events = <String>[];
      final transport = MockTransport((request, context) async {
        calls += 1;
        if (calls == 1) {
          return Response.text('retry', status: 503);
        }
        return Response.json({
          'app': request.headers.get('x-app'),
          'net': request.headers.get('x-net'),
          'attempt': context.attempt,
        });
      });

      final client = Client(
        ClientOptions(
          baseUrl: Uri.parse('https://example.com'),
          transport: transport,
          middleware: [
            RequestHeaderMiddleware('x-app', '1', events),
            AttemptHeaderMiddleware('x-net', '1', events),
          ],
        ),
      );

      final response = await client.get('/resource');
      final payload = await response.json<Map<String, Object?>>();

      expect(calls, 2);
      expect(events, ['x-app:0', 'x-net:0', 'x-net:1']);
      expect(payload['app'], '1');
      expect(payload['net'], '1');
      expect(payload['attempt'], 1);
    },
  );

  test('uses typed attributes instead of string extras', () async {
    const key = AttributeKey<String>('tenant');
    late String? tenant;

    final transport = MockTransport((request, context) async {
      tenant = context.attribute(key);
      return Response.text('ok');
    });

    final client = Client(
      ClientOptions(
        transport: transport,
        attributes: const Attributes().set(key, 'pa'),
      ),
    );

    await client.get('https://example.com');
    expect(tenant, 'pa');
  });

  test('sendResult is the single no-throw client entry', () async {
    final client = Client(
      ClientOptions(
        retryPolicy: const RetryPolicy(maxRetries: 0),
        transport: MockTransport((request, context) async {
          throw const NetworkError('down');
        }),
      ),
    );

    final result = await client.sendResult(Request('https://example.com'));
    expect(result.isFailure, isTrue);
    expect(result.error, isA<NetworkError>());
  });

  test('per-request headers override client defaults', () async {
    late Request captured;
    final client = Client(
      ClientOptions(
        defaultHeaders: {'authorization': 'Bearer default'},
        transport: MockTransport((request, context) async {
          captured = request;
          return Response.text('ok');
        }),
      ),
    );

    await client.get(
      'https://example.com',
      headers: {'authorization': 'Bearer request'},
    );

    expect(captured.headers.getAll('authorization'), ['Bearer request']);
  });

  test('emits start before prepared lifecycle events', () async {
    final events = <RequestEventType>[];
    final client = Client(
      ClientOptions(
        onEvent: (event) => events.add(event.type),
        transport: MockTransport((request, context) async {
          return Response.text('ok');
        }),
      ),
    );

    await client.get('https://example.com/events');

    expect(
      events,
      containsAllInOrder([
        RequestEventType.start,
        RequestEventType.prepared,
        RequestEventType.attemptStart,
        RequestEventType.attemptEnd,
        RequestEventType.complete,
      ]),
    );
    expect(events.indexOf(RequestEventType.start), 0);
    expect(
      events.indexOf(RequestEventType.prepared),
      greaterThan(events.indexOf(RequestEventType.start)),
    );
  });

  test('emits middleware lifecycle events with middleware detail', () async {
    final events = <RequestEvent>[];
    final headerEvents = <String>[];
    final client = Client(
      ClientOptions(
        onEvent: events.add,
        middleware: const [PassThroughMiddleware()],
        networkMiddleware: [
          AttemptHeaderMiddleware('x-net', '1', headerEvents),
        ],
        transport: MockTransport((request, context) async {
          return Response.text('ok');
        }),
      ),
    );

    await client.get('https://example.com/events');

    final middlewareEvents = events
        .where(
          (event) =>
              event.type == RequestEventType.middlewareStart ||
              event.type == RequestEventType.middlewareEnd,
        )
        .map((event) => '${event.type.name}:${event.detail}:${event.attempt}')
        .toList();
    expect(middlewareEvents, [
      'middlewareStart:PassThroughMiddleware.onRequest:0',
      'middlewareEnd:PassThroughMiddleware.onRequest:0',
      'middlewareStart:AttemptHeaderMiddleware.onAttempt:0',
      'middlewareEnd:AttemptHeaderMiddleware.onAttempt:0',
    ]);
  });

  test('complete event reports the successful retry attempt', () async {
    var calls = 0;
    final events = <RequestEvent>[];
    final client = Client(
      ClientOptions(
        onEvent: events.add,
        retryPolicy: const RetryPolicy(maxRetries: 1, baseDelay: Duration.zero),
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            return Response.text('retry', status: 503);
          }
          return Response.text('ok');
        }),
      ),
    );

    await client.get('https://example.com/retry');

    expect(
      events
          .where((event) => event.type == RequestEventType.attemptEnd)
          .map((event) => event.attempt),
      [0, 1],
    );
    expect(
      events
          .singleWhere((event) => event.type == RequestEventType.complete)
          .attempt,
      1,
    );
  });

  test('web capability does not auto-add content-length', () async {
    late Request captured;
    final client = Client(
      ClientOptions(
        transport: CapabilityTransport(PlatformCapability.web, (
          request,
          context,
        ) async {
          captured = request;
          return Response.text('ok');
        }),
      ),
    );

    await client.post('https://example.com', body: 'hello');

    expect(captured.headers.has('content-length'), isFalse);
    expect(captured.headers.has('user-agent'), isFalse);
  });

  test('explicit json null sends a JSON null body', () async {
    late Request captured;
    final client = Client(
      ClientOptions(
        transport: MockTransport((request, context) async {
          captured = request;
          return Response.text(await request.body!.text());
        }),
      ),
    );

    final response = await client.post('https://example.com/null', json: null);

    expect(await response.text(), 'null');
    expect(captured.headers.get('content-type'), contains('application/json'));
  });

  test(
    'pass-through middleware preserves downstream errors for retry',
    () async {
      var calls = 0;
      final client = Client(
        ClientOptions(
          retryPolicy: const RetryPolicy(
            maxRetries: 1,
            baseDelay: Duration.zero,
          ),
          middleware: const [PassThroughMiddleware()],
          transport: MockTransport((request, context) async {
            calls += 1;
            if (calls == 1) {
              throw StateError('socket reset');
            }
            return Response.text('ok');
          }),
        ),
      );

      final response = await client.get('https://example.com/flaky');

      expect(await response.text(), 'ok');
      expect(calls, 2);
    },
  );

  test(
    'short-circuited middleware responses still honor status policy',
    () async {
      final client = Client(
        ClientOptions(
          middleware: [
            ShortCircuitMiddleware(Response.text('fail', status: 500)),
          ],
          transport: MockTransport((request, context) async {
            fail('transport should not be reached');
          }),
        ),
      );

      await expectLater(
        client.get('https://example.com/fail'),
        throwsA(
          isA<StatusError>()
              .having((error) => error.statusResponse.status, 'status', 500)
              .having((error) => error.bodyPreview, 'bodyPreview', 'fail'),
        ),
      );
    },
  );

  test(
    'short-circuited middleware responses still honor redirect policy',
    () async {
      final client = Client(
        ClientOptions(
          middleware: [
            ShortCircuitMiddleware(
              Response(null, status: 302, headers: {'location': '/next'}),
            ),
          ],
          transport: MockTransport((request, context) async {
            fail('transport should not be reached');
          }),
        ),
      );

      await expectLater(
        client.get(
          'https://example.com/start',
          options: const RequestOptions(
            redirectPolicy: RedirectPolicy.error,
            statusPolicy: StatusPolicy.returnResponse,
          ),
        ),
        throwsA(
          isA<StatusError>().having(
            (error) => error.message,
            'message',
            'Redirect blocked by RedirectPolicy.error.',
          ),
        ),
      );
    },
  );

  test('client redirect loop follows preserved-method redirects', () async {
    var calls = 0;
    late Request redirected;
    final client = Client(
      ClientOptions(
        baseUrl: Uri.parse('https://example.com'),
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            return Response(
              null,
              status: 307,
              headers: {'location': '/target'},
            );
          }
          redirected = request;
          return Response.text(await request.body!.text(), url: request.uri);
        }),
      ),
    );

    final response = await client.put('/start', body: 'payload');

    expect(await response.text(), 'payload');
    expect(response.redirected, isTrue);
    expect(redirected.method, 'PUT');
    expect(redirected.uri.path, '/target');
    expect(calls, 2);
  });

  test('client redirect loop does not rerun request middleware', () async {
    var calls = 0;
    final events = <String>[];
    final client = Client(
      ClientOptions(
        baseUrl: Uri.parse('https://example.com'),
        middleware: [RequestHeaderMiddleware('x-app', '1', events)],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            return Response(null, status: 302, headers: {'location': '/next'});
          }
          return Response.text(request.headers.get('x-app') ?? '');
        }),
      ),
    );

    final response = await client.get('/start');

    expect(await response.text(), '1');
    expect(events, ['x-app:0']);
    expect(calls, 2);
  });

  test('short-circuited middleware redirects are followed on web', () async {
    late Request redirected;
    final client = Client(
      ClientOptions(
        baseUrl: Uri.parse('https://example.com'),
        middleware: [
          ShortCircuitMiddleware(
            Response(null, status: 302, headers: {'location': '/next'}),
          ),
        ],
        transport: CapabilityTransport(PlatformCapability.web, (
          request,
          context,
        ) async {
          redirected = request;
          return Response.text('ok', url: request.uri);
        }),
      ),
    );

    final response = await client.get('/start');

    expect(await response.text(), 'ok');
    expect(response.redirected, isTrue);
    expect(redirected.uri.path, '/next');
  });

  test('malformed redirect locations throw typed status errors', () async {
    final client = Client(
      ClientOptions(
        baseUrl: Uri.parse('https://example.com'),
        transport: MockTransport((request, context) async {
          return Response(null, status: 302, headers: {'location': 'http://['});
        }),
      ),
    );

    await expectLater(
      client.get('/start'),
      throwsA(
        isA<StatusError>()
            .having(
              (error) => error.message,
              'message',
              'Redirect response has an invalid Location header.',
            )
            .having((error) => error.statusResponse.status, 'status', 302),
      ),
    );
  });

  test('short-circuited streaming responses honor read timeout', () async {
    final client = Client(
      ClientOptions(
        timeoutPolicy: const TimeoutPolicy(
          read: Duration(milliseconds: 10),
          total: null,
        ),
        middleware: [
          ShortCircuitMiddleware(
            Response.stream(
              Stream<List<int>>.periodic(
                const Duration(seconds: 1),
                (_) => [1],
              ),
            ),
          ),
        ],
        transport: MockTransport((request, context) async {
          fail('transport should not be reached');
        }),
      ),
    );

    final response = await client.get('https://example.com/stream');

    await expectLater(
      response.bytes(),
      throwsA(
        isA<TimeoutError>().having(
          (error) => error.phase,
          'phase',
          TimeoutPhase.read,
        ),
      ),
    );
  });

  test('client redirect loop honors maxRedirects', () async {
    final client = Client(
      ClientOptions(
        baseUrl: Uri.parse('https://example.com'),
        redirectPolicy: const RedirectPolicy(
          mode: RedirectMode.follow,
          maxRedirects: 0,
        ),
        transport: MockTransport((request, context) async {
          return Response(null, status: 302, headers: {'location': '/next'});
        }),
      ),
    );

    await expectLater(
      client.get('/start'),
      throwsA(
        isA<StatusError>().having(
          (error) => error.message,
          'message',
          'Too many redirects.',
        ),
      ),
    );
  });

  test('client redirect loop ignores non-redirect 3xx statuses', () async {
    final client = Client(
      ClientOptions(
        statusPolicy: StatusPolicy.returnResponse,
        transport: MockTransport((request, context) async {
          return Response.text('choices', status: 300);
        }),
      ),
    );

    final response = await client.get('https://example.com/choices');

    expect(response.status, 300);
    expect(await response.text(), 'choices');
  });

  test(
    'client redirect loop refuses one-shot preserved-body redirects',
    () async {
      var calls = 0;
      final client = Client(
        ClientOptions(
          transport: MockTransport((request, context) async {
            calls += 1;
            return Response(null, status: 307, headers: {'location': '/next'});
          }),
        ),
      );

      await expectLater(
        client.put(
          'https://example.com/upload',
          body: Stream<List<int>>.value([1]),
        ),
        throwsA(
          isA<StatusError>().having(
            (error) => error.message,
            'message',
            'Redirect requires a replayable request body.',
          ),
        ),
      );
      expect(calls, 1);
    },
  );

  test(
    'cross-origin redirects strip auth without rerunning request middleware',
    () async {
      var calls = 0;
      late Request redirected;
      final events = <String>[];
      final client = Client(
        ClientOptions(
          middleware: [
            AuthMiddleware.staticToken('secret'),
            AttemptHeaderMiddleware('authorization', 'Bearer network', events),
          ],
          transport: MockTransport((request, context) async {
            calls += 1;
            if (calls == 1) {
              return Response(
                null,
                status: 302,
                headers: {'location': 'https://other.example/target'},
                url: request.uri,
              );
            }
            redirected = request;
            return Response.text('ok', url: request.uri);
          }),
        ),
      );

      await client.get('https://example.com/start');

      expect(redirected.uri.host, 'other.example');
      expect(redirected.headers.has('authorization'), isFalse);
    },
  );

  test(
    'cross-origin redirect marker survives redirected-origin chain',
    () async {
      var calls = 0;
      late Request finalRequest;
      final client = Client(
        ClientOptions(
          middleware: [AuthMiddleware.staticToken('secret')],
          transport: MockTransport((request, context) async {
            calls += 1;
            if (calls == 1) {
              return Response(
                null,
                status: 302,
                headers: {'location': 'https://other.example/step'},
                url: request.uri,
              );
            }
            if (calls == 2) {
              expect(request.uri.host, 'other.example');
              expect(request.headers.has('authorization'), isFalse);
              return Response(
                null,
                status: 302,
                headers: {'location': '/final'},
                url: request.uri,
              );
            }
            finalRequest = request;
            return Response.text('ok', url: request.uri);
          }),
        ),
      );

      await client.get('https://api.example.com/start');

      expect(finalRequest.uri.toString(), 'https://other.example/final');
      expect(finalRequest.headers.has('authorization'), isFalse);
    },
  );
}
