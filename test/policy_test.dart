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
}
