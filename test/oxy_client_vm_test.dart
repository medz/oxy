@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

class AddHeaderMiddleware implements OxyMiddleware {
  @override
  Future<Response> intercept(
    Request request,
    RequestOptions options,
    Next next,
  ) {
    final headers = request.headers.clone()..set('x-middleware', 'enabled');
    return next(request.copyWith(headers: headers), options);
  }
}

void main() {
  group('Oxy client (vm)', () {
    late HttpServer server;
    late Uri baseUri;
    var flakyAttempts = 0;

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

              case '/cookie/set':
                request.response.headers.add(
                  'set-cookie',
                  'sid=server-token; Path=/; HttpOnly',
                );
                request.response
                  ..statusCode = 200
                  ..write('cookie set');
                break;

              case '/status/404':
                request.response
                  ..statusCode = 404
                  ..write('not found');
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

              case '/flaky':
                flakyAttempts += 1;
                if (flakyAttempts <= 2) {
                  request.response
                    ..statusCode = 503
                    ..write('temporary failure #$flakyAttempts');
                } else {
                  request.response
                    ..statusCode = 200
                    ..write('ok #$flakyAttempts');
                }
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
      final client = Oxy(OxyConfig(baseUrl: baseUri));
      final response = await client.get('/hello');

      expect(response.status, 200);
      expect(await response.text(), 'hello oxy');
    });

    test('json shortcut for request body', () async {
      final client = Oxy(OxyConfig(baseUrl: baseUri));
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
      final client = Oxy(OxyConfig(baseUrl: baseUri));
      final response = await client.get(
        '/redirect',
        options: const RequestOptions(
          redirectPolicy: RedirectPolicy.manual,
          throwOnHttpError: false,
        ),
      );

      expect(response.status, 302);
      expect(response.headers.get('location'), isNotNull);
    });

    test('aborts in-flight requests', () async {
      final client = Oxy(OxyConfig(baseUrl: baseUri));
      final signal = AbortSignal();
      Timer(const Duration(milliseconds: 50), () => signal.abort('cancelled'));

      expect(
        client.get('/slow', options: RequestOptions(signal: signal)),
        throwsA(isA<OxyCancelledException>()),
      );
    });

    test('throws on HTTP error by default', () async {
      final client = Oxy(OxyConfig(baseUrl: baseUri));

      expect(client.get('/status/404'), throwsA(isA<OxyHttpException>()));
    });

    test('can disable throwOnHttpError per request', () async {
      final client = Oxy(OxyConfig(baseUrl: baseUri));
      final response = await client.get(
        '/status/404',
        options: const RequestOptions(throwOnHttpError: false),
      );

      expect(response.status, 404);
      expect(await response.text(), 'not found');
    });

    test('middleware can modify outgoing request', () async {
      final client = Oxy(
        OxyConfig(
          baseUrl: baseUri,
          middleware: <OxyMiddleware>[AddHeaderMiddleware()],
        ),
      );

      final response = await client.get('/echo');
      final payload = await response.json<Map<String, dynamic>>();

      expect(
        (payload['headers'] as Map<String, dynamic>)['x-middleware'],
        equals('enabled'),
      );
    });

    test('request id middleware injects request id header', () async {
      final client = Oxy(
        OxyConfig(
          baseUrl: baseUri,
          middleware: <OxyMiddleware>[
            RequestIdMiddleware(requestIdProvider: (_, _) => 'trace-001'),
          ],
        ),
      );

      final response = await client.get('/echo');
      final payload = await response.json<Map<String, dynamic>>();

      expect(
        (payload['headers'] as Map<String, dynamic>)['x-request-id'],
        equals('trace-001'),
      );
    });

    test(
      'auto injects CookieMiddleware when cookieJar is configured',
      () async {
        final client = Oxy(
          OxyConfig(baseUrl: baseUri, cookieJar: MemoryCookieJar()),
        );

        final setCookieResponse = await client.get('/cookie/set');
        expect(setCookieResponse.status, 200);

        final echoResponse = await client.get('/echo');
        final payload = await echoResponse.json<Map<String, dynamic>>();

        expect(
          (payload['headers'] as Map<String, dynamic>)['cookie'],
          contains('sid=server-token'),
        );
      },
    );

    test(
      'request CookieMiddleware prevents duplicate auto injection',
      () async {
        final globalJar = MemoryCookieJar();
        final requestJar = MemoryCookieJar();

        await globalJar.save(baseUri, [
          OxyCookie(
            name: 'global',
            value: '1',
            domain: baseUri.host,
            path: '/',
          ),
        ]);
        await requestJar.save(baseUri, [
          OxyCookie(
            name: 'request',
            value: '2',
            domain: baseUri.host,
            path: '/',
          ),
        ]);

        final client = Oxy(OxyConfig(baseUrl: baseUri, cookieJar: globalJar));

        final response = await client.get(
          '/echo',
          options: RequestOptions(
            middleware: <OxyMiddleware>[CookieMiddleware(requestJar)],
          ),
        );
        final payload = await response.json<Map<String, dynamic>>();

        expect(
          (payload['headers'] as Map<String, dynamic>)['cookie'],
          equals('request=2'),
        );
      },
    );

    test('retries transient failures for idempotent GET', () async {
      flakyAttempts = 0;
      final client = Oxy(
        OxyConfig(
          baseUrl: baseUri,
          retryPolicy: const RetryPolicy(maxRetries: 2),
        ),
      );

      final response = await client.get('/flaky');
      expect(response.status, 200);
      expect(await response.text(), 'ok #3');
    });

    test('throws retry exhausted when attempts are not enough', () async {
      flakyAttempts = 0;
      final client = Oxy(
        OxyConfig(
          baseUrl: baseUri,
          retryPolicy: const RetryPolicy(maxRetries: 1),
        ),
      );

      expect(client.get('/flaky'), throwsA(isA<OxyRetryExhaustedException>()));
    });
  });
}
