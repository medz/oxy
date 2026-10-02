@TestOn('browser || node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:oxy/oxy.dart';
import 'package:oxy/src/transport/transport.web.dart' as web;
import 'package:test/test.dart';

Future<(Client, void Function())> loopbackClient({
  ClientOptions? options,
}) async {
  final server = spawnHybridUri('fixtures/http_server.dart');
  var closed = false;
  void closeServer() {
    if (closed) return;
    closed = true;
    server.sink.add('close');
  }

  addTearDown(closeServer);
  final baseUrl = Uri.parse(await server.stream.first as String);
  final client = Client(
    (options ?? const ClientOptions()).copyWith(baseUrl: baseUrl),
  );
  addTearDown(client.close);
  return (client, closeServer);
}

void main() {
  test('default Web transport sends actual HTTP GET and JSON POST', () async {
    final (client, _) = await loopbackClient();
    final get = await client.get('/health');
    expect(await get.json<Map<String, Object?>>(), {
      'method': 'GET',
      'body': '',
      'path': '/health',
    });
    final post = await client.post('/echo', json: {'name': 'Oxy 🌍'});
    final echo = await post.json<Map<String, Object?>>();
    expect(echo['method'], 'POST');
    expect(echo['body'], '{"name":"Oxy 🌍"}');
    final bytes = await (await client.get('/bytes')).bytes();
    expect(
      bytes,
      orderedEquals(List<int>.generate(128 * 1024, (i) => i % 251)),
    );
  });

  test(
    'unsupported request streaming advertises buffering and preserves HTTP payload',
    () async {
      final transport = web.WebTransport(requestStreamsSupported: false);
      final (client, _) = await loopbackClient(
        options: ClientOptions(transport: transport),
      );
      expect(client.transport.capability.streamingRequestBody, isFalse);
      final response = await client.post(
        '/echo',
        body: Stream<Uint8List>.fromIterable([
          Uint8List.fromList(utf8.encode('hello ')),
          Uint8List.fromList(utf8.encode('stream 🌍')),
        ]),
      );
      final echo = await response.json<Map<String, Object?>>();
      expect(echo['body'], 'hello stream 🌍');
    },
  );

  test(
    'caller abort interrupts a pending HTTP body read with CancelError',
    () async {
      final (client, closeServer) = await loopbackClient(
        options: const ClientOptions(timeoutPolicy: TimeoutPolicy(total: null)),
      );
      final signal = AbortSignal();
      final response = await client
          .get('/stream', options: RequestOptions(signal: signal))
          .timeout(const Duration(seconds: 3));
      final reader = StreamIterator(response.stream());
      addTearDown(() {
        closeServer();
        return reader.cancel();
      });
      expect(
        await reader.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(utf8.decode(reader.current), 'first');
      final pending = reader.moveNext();
      signal.abort('user stopped');
      await expectLater(
        pending.timeout(const Duration(seconds: 2)),
        throwsA(
          isA<CancelError>().having((e) => e.reason, 'reason', 'user stopped'),
        ),
      );
    },
  );

  test('read timeout interrupts a stalled HTTP response body', () async {
    final (client, closeServer) = await loopbackClient(
      options: const ClientOptions(
        timeoutPolicy: TimeoutPolicy(
          total: null,
          read: Duration(milliseconds: 80),
        ),
      ),
    );
    final signal = AbortSignal();
    final response = await client
        .get('/stream', options: RequestOptions(signal: signal))
        .timeout(const Duration(seconds: 3));
    final reader = StreamIterator(response.stream());
    addTearDown(() {
      closeServer();
      return reader.cancel();
    });
    expect(await reader.moveNext().timeout(const Duration(seconds: 3)), isTrue);
    await expectLater(
      reader.moveNext().timeout(const Duration(seconds: 2)),
      throwsA(
        isA<TimeoutError>().having((e) => e.phase, 'phase', TimeoutPhase.read),
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
  });
}
