@TestOn('vm')
library;

import 'dart:async';

import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native capability reflects exposed configuration while HTTP works',
    () async {
      final fixture = spawnHybridUri('fixtures/http_server.dart');
      addTearDown(() => fixture.sink.add('close'));
      final baseUrl = Uri.parse(await fixture.stream.first as String);
      final client = Client(ClientOptions(baseUrl: baseUrl));
      addTearDown(client.close);
      expect(client.transport.capability.proxyConfiguration, isFalse);
      expect(client.transport.capability.tlsConfiguration, isFalse);
      final result = await (await client.get(
        '/health',
      )).json<Map<String, Object?>>();
      expect(result['method'], 'GET');
      expect(
        await (await client.get('/bytes')).bytes(),
        orderedEquals(List<int>.generate(128 * 1024, (i) => i % 251)),
      );
    },
  );

  test('native caller abort ends a pending response body read', () async {
    final fixture = spawnHybridUri('fixtures/http_server.dart');
    var closed = false;
    void closeFixture() {
      if (closed) return;
      closed = true;
      fixture.sink.add('close');
    }

    addTearDown(closeFixture);
    final baseUrl = Uri.parse(await fixture.stream.first as String);
    final client = Client(
      ClientOptions(
        baseUrl: baseUrl,
        timeoutPolicy: const TimeoutPolicy(total: null),
      ),
    );
    addTearDown(client.close);
    final signal = AbortSignal();
    final response = await client.get(
      '/stream',
      options: RequestOptions(signal: signal),
    );
    final reader = StreamIterator(response.stream());
    addTearDown(() {
      closeFixture();
      return reader.cancel();
    });
    expect(await reader.moveNext().timeout(const Duration(seconds: 2)), isTrue);
    final pending = reader.moveNext();
    signal.abort('user stopped');
    await expectLater(
      pending.timeout(const Duration(seconds: 2)),
      throwsA(
        isA<CancelError>().having((e) => e.reason, 'reason', 'user stopped'),
      ),
    );
    expect(
      (await (await client.get(
        '/health',
      )).json<Map<String, Object?>>())['method'],
      'GET',
    );
  });

  test(
    'native read timeout preserves the caller signal and ends a stalled read',
    () async {
      final fixture = spawnHybridUri('fixtures/http_server.dart');
      var closed = false;
      void closeFixture() {
        if (closed) return;
        closed = true;
        fixture.sink.add('close');
      }

      addTearDown(closeFixture);
      final baseUrl = Uri.parse(await fixture.stream.first as String);
      final client = Client(
        ClientOptions(
          baseUrl: baseUrl,
          timeoutPolicy: const TimeoutPolicy(
            total: null,
            read: Duration(milliseconds: 80),
          ),
        ),
      );
      addTearDown(client.close);
      final signal = AbortSignal();
      final response = await client.get(
        '/stream',
        options: RequestOptions(signal: signal),
      );
      final reader = StreamIterator(response.stream());
      addTearDown(() {
        closeFixture();
        return reader.cancel();
      });
      expect(
        await reader.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      await expectLater(
        reader.moveNext().timeout(const Duration(seconds: 2)),
        throwsA(
          isA<TimeoutError>().having(
            (e) => e.phase,
            'phase',
            TimeoutPhase.read,
          ),
        ),
      );
      expect(signal.aborted, isFalse);
      expect(signal.reason, isNull);
      expect(
        (await (await client.get(
          '/health',
        )).json<Map<String, Object?>>())['method'],
        'GET',
      );
    },
  );
}
