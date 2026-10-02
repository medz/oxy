import 'dart:async';

import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  const policies = {
    'unlimited': TimeoutPolicy(total: null),
    'default total': TimeoutPolicy(),
    'read only': TimeoutPolicy(total: null, read: Duration(seconds: 30)),
  };
  for (final entry in policies.entries) {
    test(
      'body cancellation interrupts a pending read with ${entry.key}',
      () async {
        final fixture = spawnHybridUri('fixtures/http_server.dart');
        var closed = false;
        void closeFixture() {
          if (closed) return;
          closed = true;
          fixture.sink.add('close');
        }

        final baseUrl = Uri.parse(await fixture.stream.first as String);
        final client = Client(
          ClientOptions(baseUrl: baseUrl, timeoutPolicy: entry.value),
        );
        final caller = AbortSignal();
        final response = await client.get(
          '/stream',
          options: RequestOptions(signal: caller),
        );
        final reader = StreamIterator(response.stream());
        try {
          expect(
            await reader.moveNext().timeout(const Duration(seconds: 2)),
            isTrue,
          );
          final pending = reader.moveNext();
          // Cancel only after the source has entered its asynchronous read.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await reader.cancel().timeout(const Duration(seconds: 2));
          expect(await pending, isFalse);
          expect(caller.aborted, isFalse);
          expect(
            (await (await client.get('/health')).json<Map>())['method'],
            'GET',
          );
        } finally {
          caller.abort('fixture cleanup');
          closeFixture();
          await reader.cancel();
          await client.close();
        }
      },
    );
  }
}
