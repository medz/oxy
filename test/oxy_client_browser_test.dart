@TestOn('browser')
library;

import 'dart:convert';

import 'package:oxy/oxy.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

extension on StreamChannel {
  Future<int> get firstAsInt async => ((await stream.first) as num).toInt();
}

void main() {
  group('Oxy client (browser)', () {
    late Uri echoUri;
    late String textUrl;
    late String jsonUrl;

    setUpAll(() async {
      final channel = spawnHybridCode(
        r'''
        import 'dart:convert';
        import 'dart:io';

        import 'package:stream_channel/stream_channel.dart';

        Future<void> hybridMain(StreamChannel channel) async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

          channel.sink.add(server.port);

          await for (final request in server) {
            request.response.headers
              ..set('access-control-allow-origin', '*')
              ..set('access-control-allow-headers', 'content-type')
              ..set('access-control-allow-methods', 'POST, OPTIONS');

            if (request.method == 'OPTIONS') {
              request.response
                ..statusCode = HttpStatus.noContent
                ..close();
              continue;
            }

            if (request.uri.path != '/echo') {
              request.response
                ..statusCode = HttpStatus.notFound
                ..close();
              continue;
            }

            final body = await utf8.decodeStream(request);
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'method': request.method, 'body': body}),
            );
            await request.response.close();
          }
        }
        ''',
        stayAlive: true,
      );

      echoUri = Uri.parse('http://127.0.0.1:${await channel.firstAsInt}/echo');
    });

    setUp(() {
      textUrl = Uri.dataFromString(
        'hello browser',
        mimeType: 'text/plain',
        encoding: utf8,
      ).toString();
      jsonUrl = Uri.dataFromString(
        jsonEncode(<String, Object?>{'ok': true}),
        mimeType: 'application/json',
        encoding: utf8,
      ).toString();
    });

    test('gets text from data URL', () async {
      final client = Oxy();
      final response = await client.get(textUrl);

      expect(response.status, 200);
      expect(await response.text(), 'hello browser');
    });

    test('supports typed decode on browser transport', () async {
      final client = Oxy();

      final decoded = await client.getDecoded<bool>(
        jsonUrl,
        decoder: (value) => (value as Map<String, Object?>)['ok'] as bool,
      );

      expect(decoded, isTrue);
    });

    test('safeGetDecoded returns OxySuccess on browser', () async {
      final client = Oxy();

      final result = await client.safeGetDecoded<bool>(
        jsonUrl,
        decoder: (value) => (value as Map<String, Object?>)['ok'] as bool,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, isTrue);
    });

    test('safeGet captures abort as OxyFailure', () async {
      final client = Oxy();
      final signal = AbortSignal()..abort('cancelled before send');

      final result = await client.safeGet(
        textUrl,
        options: RequestOptions(signal: signal),
      );

      expect(result.isFailure, isTrue);
      expect(result.error, isA<OxyCancelledException>());
    });

    test('posts JSON body to HTTP/1.1 endpoint', () async {
      final client = Oxy();
      final response = await client.post(
        echoUri.toString(),
        headers: Headers({'content-type': 'application/json'}),
        body: jsonEncode({
          'name': 'Browser Repro',
          'email': 'browser-repro@spry.dev',
        }),
      );

      expect(response.status, 200);
      expect(
        await response.json<Map<String, Object?>>(),
        {
          'method': 'POST',
          'body': jsonEncode({
            'name': 'Browser Repro',
            'email': 'browser-repro@spry.dev',
          }),
        },
      );
    });

    test('reports send and receive progress on browser', () async {
      final client = Oxy();
      final sent = <TransferProgress>[];
      final received = <TransferProgress>[];

      final response = await client.request(
        'GET',
        textUrl,
        onSendProgress: sent.add,
        onReceiveProgress: received.add,
      );
      final text = await response.text();

      expect(text, 'hello browser');
      expect(sent, isNotEmpty);
      expect(sent.first.transferred, 0);
      expect(sent.last.transferred, 0);
      expect(sent.last.total, isNull);
      expect(received, isNotEmpty);
      expect(received.last.transferred, greaterThan(0));
    });
  });
}
