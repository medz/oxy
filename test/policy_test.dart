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

  test('status policy preserves invalid UTF-8 preview bodies', () async {
    final payload = Uint8List.fromList([0xff, 0xfe, 0x61]);
    final client = Client(
      ClientOptions(
        errorBodyPreviewLimit: 64,
        transport: MockTransport((request, context) async {
          return Response.bytes(payload, status: 400);
        }),
      ),
    );

    try {
      await client.get('https://example.com/binary-error');
      fail('Expected StatusError.');
    } on StatusError catch (error) {
      expect(error.bodyPreview, isNull);
      expect(await error.statusResponse.bytes(), orderedEquals(payload));
      expect(await error.statusResponse.bytes(), orderedEquals(payload));
    }
  });

  test('status policy restores over-limit preview bodies', () async {
    final payload = Uint8List.fromList('0123456789'.codeUnits);
    final client = Client(
      ClientOptions(
        errorBodyPreviewLimit: 4,
        transport: MockTransport((request, context) async {
          return Response.stream(
            Stream<List<int>>.fromIterable([
              payload.sublist(0, 3),
              payload.sublist(3),
            ]),
            status: 400,
          );
        }),
      ),
    );

    try {
      await client.get('https://example.com/large-error');
      fail('Expected StatusError.');
    } on StatusError catch (error) {
      expect(error.bodyPreview, isNull);
      expect(await error.statusResponse.bytes(), orderedEquals(payload));
    }
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

  test('retry clears aborted attempt signals between attempts', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        retryPolicy: const RetryPolicy(maxRetries: 1, baseDelay: Duration.zero),
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            final timeout = TimeoutError(
              phase: TimeoutPhase.send,
              duration: const Duration(milliseconds: 10),
              request: request,
              sent: true,
            );
            context.signal?.abort(timeout);
            throw timeout;
          }
          return Response.text('ok');
        }),
      ),
    );

    final response = await client.get('https://example.com/flaky-send');

    expect(await response.text(), 'ok');
    expect(calls, 2);
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

  test('total timeout closes hooks promptly once', () async {
    final release = Completer<void>();
    final errors = <Object>[];
    var finallyCalls = 0;
    var responseCalls = 0;
    var completeEvents = 0;
    final client = Client(
      ClientOptions(
        timeoutPolicy: const TimeoutPolicy(total: Duration(milliseconds: 20)),
        retryPolicy: const RetryPolicy(maxRetries: 0),
        hooks: Hooks(
          onResponse: (request, response, context) {
            responseCalls += 1;
            return response;
          },
          onError: (request, error, context) {
            errors.add(error);
          },
          onFinally: (request, context) {
            finallyCalls += 1;
          },
        ),
        onEvent: (event) {
          if (event.type == RequestEventType.complete) {
            completeEvents += 1;
          }
        },
        transport: MockTransport((request, context) async {
          await release.future;
          return Response.text('late');
        }),
      ),
    );

    await expectLater(
      client.get('https://example.com/slow-hooks'),
      throwsA(isA<TimeoutError>()),
    );

    expect(errors, hasLength(1));
    expect(errors.single, isA<TimeoutError>());
    expect(finallyCalls, 1);

    release.complete();
    await Future<void>.delayed(Duration.zero);

    expect(responseCalls, 0);
    expect(completeEvents, 0);
    expect(errors, hasLength(1));
    expect(finallyCalls, 1);
  });

  test('total timeout applies while consuming response body', () async {
    final aborted = Completer<void>();
    final client = Client(
      ClientOptions(
        timeoutPolicy: const TimeoutPolicy(total: Duration(milliseconds: 30)),
        retryPolicy: const RetryPolicy(maxRetries: 0),
        transport: MockTransport((request, context) async {
          context.signal?.onAbort(() {
            if (!aborted.isCompleted) {
              aborted.complete();
            }
          });
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

    final response = await client.get('https://example.com/stalled-body');

    await expectLater(
      response.bytes(),
      throwsA(
        isA<TimeoutError>().having(
          (error) => error.phase,
          'phase',
          TimeoutPhase.total,
        ),
      ),
    );
    await expectLater(
      aborted.future.timeout(const Duration(seconds: 1)),
      completes,
    );
  });

  test('default total timeout preserves replayable response bodies', () async {
    final client = Client(
      ClientOptions(
        transport: MockTransport((request, context) async {
          return Response.text('cached');
        }),
      ),
    );

    final response = await client.get('https://example.com/replayable');

    expect(await response.text(), 'cached');
    expect(await response.text(), 'cached');
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
    final client = Client(
      ClientOptions(
        retryPolicy: const RetryPolicy(maxRetries: 1, baseDelay: Duration.zero),
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            throw TimeoutError(
              phase: TimeoutPhase.firstByte,
              duration: const Duration(milliseconds: 10),
              request: request,
              sent: true,
            );
          }
          return Response.text('ok');
        }),
      ),
    );

    final response = await client.get('https://example.com/flaky-first-byte');

    expect(await response.text(), 'ok');
    expect(calls, 2);
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

  test('retry policy honors RFC850 Retry-After dates in this century', () {
    final retryAt = DateTime.now().toUtc().add(const Duration(minutes: 5));
    final response = Response.text(
      'busy',
      status: 503,
      headers: {'retry-after': _formatRfc850Date(retryAt)},
    );

    final delay = const RetryPolicy(
      baseDelay: Duration(milliseconds: 100),
      jitterRatio: 0,
    ).delayFor(0, response: response);

    expect(delay, greaterThan(Duration.zero));
    expect(delay, lessThanOrEqualTo(const Duration(minutes: 5)));
  });

  test('retry policy rolls over RFC850 dates more than 50 years ahead', () {
    final now = DateTime.now().toUtc();
    final retryAt = DateTime.utc(
      now.year + 50,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    ).add(const Duration(days: 1));
    final response = Response.text(
      'busy',
      status: 503,
      headers: {'retry-after': _formatRfc850Date(retryAt)},
    );

    final delay = const RetryPolicy().delayFor(0, response: response);

    expect(delay, Duration.zero);
  });

  test('retry policy ignores invalid Retry-After dates', () {
    final response = Response.text(
      'busy',
      status: 503,
      headers: {'retry-after': 'Wed, 99 Nope 2099 07:28:00 GMT'},
    );

    final delay = const RetryPolicy(
      baseDelay: Duration(milliseconds: 100),
      jitterRatio: 0,
    ).delayFor(0, response: response);

    expect(delay, const Duration(milliseconds: 100));
  });

  test('retry policy accepts obsolete HTTP-date Retry-After values', () {
    final response = Response.text(
      'busy',
      status: 503,
      headers: {'retry-after': 'Wednesday, 21-Oct-99 07:28:00 GMT'},
    );

    final delay = const RetryPolicy().delayFor(0, response: response);

    expect(delay, Duration.zero);
  });

  test('retry policy rejects negative delay configuration', () {
    expect(
      () =>
          RetryPolicy(baseDelay: const Duration(milliseconds: -1)).delayFor(0),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => RetryPolicy(maxDelay: const Duration(milliseconds: -1)).delayFor(0),
      throwsA(isA<AssertionError>()),
    );
  });
}

const _longWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatRfc850Date(DateTime date) {
  date = date.toUtc();
  final day = date.day.toString().padLeft(2, '0');
  final year = (date.year % 100).toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final second = date.second.toString().padLeft(2, '0');
  return '${_longWeekdays[date.weekday - 1]}, '
      '$day-${_shortMonths[date.month - 1]}-$year '
      '$hour:$minute:$second GMT';
}
