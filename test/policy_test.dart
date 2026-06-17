import 'dart:async';
import 'dart:typed_data';

import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';
import 'package:test/test.dart';

void main() {
  test('status policy throws typed StatusError with bounded preview', () async {
    final client = Client(
      ClientOptions(
        errorBodyPreviewLimit: 64,
        transport: MockTransport((request, context) async {
          return Response.text('not found', status: 404, statusText: 'Nope');
        }),
      ),
    );

    await expectLater(
      client.get('https://example.com/missing'),
      throwsA(
        isA<StatusError>()
            .having((error) => error.statusResponse.status, 'status', 404)
            .having((error) => error.bodyPreview, 'preview', 'not found'),
      ),
    );
  });

  test('status policy can return non-2xx responses', () async {
    final client = Client(
      ClientOptions(
        statusPolicy: StatusPolicy.returnResponse,
        transport: MockTransport((request, context) async {
          return Response.text('missing', status: 404);
        }),
      ),
    );

    final response = await client.get('https://example.com/missing');
    expect(response.status, 404);
  });

  test('retry skips non-replayable body instead of resending stream', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text('temporary', status: 503);
        }),
      ),
    );

    await expectLater(
      client.put(
        'https://example.com/upload',
        body: Stream<Uint8List>.fromIterable([
          Uint8List.fromList([1]),
        ]),
      ),
      throwsA(isA<StatusError>()),
    );
    expect(calls, 1);
  });

  test('abort signal cancels retry delay', () async {
    final signal = AbortSignal();
    final client = Client(
      ClientOptions(
        retryPolicy: const RetryPolicy(
          baseDelay: Duration(seconds: 5),
          maxDelay: Duration(seconds: 5),
        ),
        transport: MockTransport((request, context) async {
          scheduleMicrotask(() => signal.abort('stop'));
          return Response.text('temporary', status: 503);
        }),
      ),
    );

    await expectLater(
      client.get(
        'https://example.com/flaky',
        options: RequestOptions(signal: signal),
      ),
      throwsA(isA<CancelError>()),
    );
  });

  test('pre-aborted signal returns typed CancelError', () async {
    final signal = AbortSignal()..abort('stop');
    final client = Client(
      ClientOptions(
        transport: MockTransport((request, context) async {
          return Response.text('unreachable');
        }),
      ),
    );

    await expectLater(
      client.get(
        'https://example.com/cancelled',
        options: RequestOptions(signal: signal),
      ),
      throwsA(
        isA<CancelError>().having((error) => error.reason, 'reason', 'stop'),
      ),
    );
  });

  test('total timeout aborts in-flight transport work', () async {
    final aborted = Completer<void>();
    final client = Client(
      ClientOptions(
        timeoutPolicy: const TimeoutPolicy(total: Duration(milliseconds: 10)),
        retryPolicy: const RetryPolicy(maxRetries: 0),
        transport: MockTransport((request, context) async {
          context.signal?.onAbort(() {
            if (!aborted.isCompleted) {
              aborted.complete();
            }
          });
          await Future<void>.delayed(const Duration(seconds: 1));
          return Response.text('late');
        }),
      ),
    );

    await expectLater(
      client.get('https://example.com/slow'),
      throwsA(isA<TimeoutError>()),
    );
    await expectLater(
      aborted.future.timeout(const Duration(seconds: 1)),
      completes,
    );
  });

  test('retry drains large transient bodies without failing', () async {
    var calls = 0;
    final large = Uint8List(96 * 1024);
    final client = Client(
      ClientOptions(
        retryPolicy: const RetryPolicy(maxRetries: 1, baseDelay: Duration.zero),
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            return Response.bytes(large, status: 503);
          }
          return Response.text('ok');
        }),
      ),
    );

    final response = await client.get('https://example.com/flaky');

    expect(await response.text(), 'ok');
    expect(calls, 2);
  });

  test('read timeout applies while consuming response body', () async {
    final client = Client(
      ClientOptions(
        timeoutPolicy: const TimeoutPolicy(
          read: Duration(milliseconds: 10),
          total: null,
        ),
        transport: MockTransport((request, context) async {
          return Response.stream(
            Stream<List<int>>.fromFuture(
              Future<List<int>>.delayed(
                const Duration(milliseconds: 100),
                () => [1],
              ),
            ),
          );
        }),
      ),
    );

    final response = await client.get('https://example.com/stalled');
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

  test('first-byte timeout remains retryable', () async {
    var calls = 0;
    final aborted = Completer<void>();
    final client = Client(
      ClientOptions(
        timeoutPolicy: const TimeoutPolicy(
          firstByte: Duration(milliseconds: 10),
          total: null,
        ),
        retryPolicy: const RetryPolicy(maxRetries: 1, baseDelay: Duration.zero),
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            context.signal?.onAbort(() {
              if (!aborted.isCompleted) {
                aborted.complete();
              }
            });
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          return Response.text('ok');
        }),
      ),
    );

    final response = await client.get('https://example.com/flaky-first-byte');

    expect(await response.text(), 'ok');
    expect(calls, 2);
    await expectLater(
      aborted.future.timeout(const Duration(seconds: 1)),
      completes,
    );
  });

  test('retry policy honors HTTP-date Retry-After values', () {
    final response = Response.text(
      'busy',
      status: 503,
      headers: {'retry-after': 'Wed, 21 Oct 2099 07:28:00 GMT'},
    );

    final delay = const RetryPolicy().delayFor(0, response: response);

    expect(delay, greaterThan(const Duration(days: 1)));
  });
}
