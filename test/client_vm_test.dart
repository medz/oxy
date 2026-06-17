@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('Client VM transport', () {
    late HttpServer server;
    late Uri baseUrl;
    var flakyCalls = 0;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = Uri.parse('http://${server.address.host}:${server.port}');

      unawaited(
        server.forEach((request) async {
          try {
            switch (request.uri.path) {
              case '/hello':
                request.response.write('hello oxy');
              case '/echo':
                final body = await utf8.decodeStream(request);
                request.response.headers.contentType = ContentType.json;
                request.response.write(
                  jsonEncode({
                    'method': request.method,
                    'body': body,
                    'query': request.uri.queryParameters,
                    'ua': request.headers.value('user-agent'),
                  }),
                );
              case '/flaky':
                flakyCalls += 1;
                if (flakyCalls == 1) {
                  request.response
                    ..statusCode = 503
                    ..write('try again');
                } else {
                  request.response.write('ok');
                }
              case '/slow':
                await Future<void>.delayed(const Duration(milliseconds: 200));
                request.response.write('slow');
              case '/redirect307':
                request.response
                  ..statusCode = 307
                  ..headers.set(HttpHeaders.locationHeader, '/echo');
              default:
                request.response
                  ..statusCode = 404
                  ..write('missing');
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

    test(
      'uses baseUrl, query merge, json body, and native transport',
      () async {
        final client = Client(ClientOptions(baseUrl: baseUrl));
        addTearDown(client.close);

        final response = await client.post(
          '/echo?existing=1',
          query: {'page': 2},
          json: {'name': 'oxy'},
        );
        final payload = await response.json<Map<String, Object?>>();

        expect(payload['method'], 'POST');
        expect(payload['body'], '{"name":"oxy"}');
        expect(payload['query'], {'existing': '1', 'page': '2'});
        expect(payload['ua'], contains('oxy/0.3.0'));
      },
    );

    test('retries replayable idempotent requests', () async {
      flakyCalls = 0;
      final client = Client(ClientOptions(baseUrl: baseUrl));
      addTearDown(client.close);

      final response = await client.get('/flaky');

      expect(await response.text(), 'ok');
      expect(flakyCalls, 2);
    });

    test('total timeout throws TimeoutError and cancels operation', () async {
      final client = Client(
        ClientOptions(
          baseUrl: baseUrl,
          timeoutPolicy: const TimeoutPolicy(total: Duration(milliseconds: 50)),
          retryPolicy: const RetryPolicy(maxRetries: 0),
        ),
      );
      addTearDown(client.close);

      await expectLater(client.get('/slow'), throwsA(isA<TimeoutError>()));
    });

    test(
      'follows native 307 redirects with method and body preserved',
      () async {
        final client = Client(ClientOptions(baseUrl: baseUrl));
        addTearDown(client.close);

        final response = await client.put('/redirect307', body: 'payload');
        final payload = await response.json<Map<String, Object?>>();

        expect(payload['method'], 'PUT');
        expect(payload['body'], 'payload');
        expect(response.redirected, isTrue);
      },
    );
  });
}
