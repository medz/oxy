@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('Oxy client (vm)', () {
    late HttpServer server;
    late Uri baseUri;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://${server.address.host}:${server.port}');

      unawaited(
        server.forEach((request) async {
          try {
            switch (request.uri.path) {
              case '/hello':
                request.response
                  ..statusCode = 200
                  ..write('hello oxy');
                break;

              case '/json':
                request.response.headers.contentType = ContentType.json;
                request.response.write(jsonEncode({'ok': true}));
                break;

              case '/echo':
                request.response.headers.contentType = ContentType.json;
                final body = await utf8.decodeStream(request);
                final headerMap = <String, String>{};
                request.headers.forEach((name, values) {
                  headerMap[name] = values.join(',');
                });
                request.response.write(
                  jsonEncode({
                    'method': request.method,
                    'body': body,
                    'headers': headerMap,
                  }),
                );
                break;

              case '/redirect':
                request.response
                  ..statusCode = 302
                  ..headers.set(
                    'location',
                    baseUri.resolve('/hello').toString(),
                  );
                break;

              case '/slow':
                await Future<void>.delayed(const Duration(milliseconds: 250));
                request.response
                  ..statusCode = 200
                  ..write('slow done');
                break;

              default:
                request.response
                  ..statusCode = 404
                  ..write('not found');
            }
          } finally {
            await request.response.close();
          }
        }),
      );
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    test('baseURL + GET', () async {
      final client = Oxy(baseURL: baseUri);
      final response = await client.get('/hello');

      expect(response.status, 200);
      expect(await response.text(), 'hello oxy');
    });

    test('json shortcut for request body', () async {
      final client = Oxy(baseURL: baseUri);
      final response = await client.post('/echo', json: {'name': 'oxy'});
      final payload = await response.json<Map<String, dynamic>>();

      expect(payload['method'], 'POST');
      expect(payload['body'], jsonEncode({'name': 'oxy'}));
      expect(
        (payload['headers'] as Map<String, dynamic>)['content-type'],
        contains('application/json'),
      );
    });

    test('manual redirect policy', () async {
      final client = Oxy(baseURL: baseUri);
      final response = await client.get(
        '/redirect',
        options: const FetchOptions(redirect: RedirectPolicy.manual),
      );

      expect(response.status, 302);
      expect(response.headers.get('location'), isNotNull);
    });

    test('aborts in-flight requests', () async {
      final client = Oxy(baseURL: baseUri);
      final signal = AbortSignal();
      Timer(const Duration(milliseconds: 50), () => signal.abort('cancelled'));

      expect(
        client.get('/slow', options: FetchOptions(signal: signal)),
        throwsA('cancelled'),
      );
    });
  });
}
