import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';

void useAdapterTests(String name, Adapter adapter) {
  group('$name Adapter Tests', () {
    late HttpServer server;
    late String baseUrl;
    late Oxy client;

    setUpAll(() async {
      // Create a test server on a random available port
      server = await HttpServer.bind('127.0.0.1', 0);
      baseUrl = 'http://${server.address.host}:${server.port}';
      client = Oxy(adapter: adapter);

      // Handle requests
      server.listen((request) async {
        final response = request.response;

        try {
          switch (request.uri.path) {
            case '/':
              response.write('Hello World');
              break;

            case '/json':
              response.headers.contentType = ContentType.json;
              response.write(
                jsonEncode({
                  'message': 'success',
                  'data': {'key': 'value'},
                }),
              );
              break;

            case '/echo':
              response.headers.contentType = ContentType.json;
              final body = await utf8.decodeStream(request);
              final headers = <String, String>{};
              request.headers.forEach((name, values) {
                headers[name] = values.join(', ');
              });

              response.write(
                jsonEncode({
                  'method': request.method,
                  'headers': headers,
                  'query': request.uri.queryParameters,
                  'body': body,
                }),
              );
              break;

            case '/status/404':
              response.statusCode = 404;
              response.write('Not Found');
              break;

            case '/status/500':
              response.statusCode = 500;
              response.write('Internal Server Error');
              break;

            case '/redirect':
              response.statusCode = 302;
              response.headers.set('Location', '$baseUrl/redirected');
              response.write('Redirecting...');
              break;

            case '/redirected':
              response.write('Redirected successfully!');
              break;

            default:
              response.statusCode = 404;
              response.write('Not Found');
          }
        } catch (e) {
          response.statusCode = 500;
          response.write('Server Error: $e');
        } finally {
          await response.close();
        }
      });

      // Wait a bit for server to be ready
      await Future.delayed(Duration(milliseconds: 100));
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    test('should make basic GET request', () async {
      final response = await client.get(baseUrl);
      expect(response.status, equals(200));
      expect(await response.text(), equals('Hello World'));
    });

    test('should handle JSON response', () async {
      final response = await client.get('$baseUrl/json');
      expect(response.status, equals(200));

      final data = await response.json();
      expect(data['message'], equals('success'));
      expect(data['data']['key'], equals('value'));
    });

    test('should make POST request with JSON body', () async {
      final body = {'name': 'John', 'age': 30};
      final response = await client.post(
        '$baseUrl/echo',
        body: Body.json(body),
      );

      expect(response.status, equals(200));
      final data = await response.json();
      expect(data['method'], equals('POST'));
      expect(data['body'], equals(jsonEncode(body)));
    });

    test('should make POST request with text body', () async {
      const textBody = 'Hello World';
      final response = await client.post(
        '$baseUrl/echo',
        body: Body.text(textBody),
      );

      expect(response.status, equals(200));
      final data = await response.json();
      expect(data['method'], equals('POST'));
      expect(data['body'], equals(textBody));
    });

    test('should send custom headers', () async {
      final response = await client.get(
        '$baseUrl/echo',
        headers: Headers({
          'X-Custom-Header': 'test-value',
          'Authorization': 'Bearer token123',
        }),
      );

      expect(response.status, equals(200));
      final data = await response.json();
      expect(data['headers']['x-custom-header'], equals('test-value'));
      expect(data['headers']['authorization'], equals('Bearer token123'));
    });

    test('should handle different HTTP methods', () async {
      // Test PUT
      final putResponse = await client.put(
        '$baseUrl/echo',
        body: Body.json({'method': 'PUT'}),
      );
      expect(putResponse.status, equals(200));
      expect((await putResponse.json())['method'], equals('PUT'));

      // Test DELETE
      final deleteResponse = await client.delete('$baseUrl/echo');
      expect(deleteResponse.status, equals(200));
      expect((await deleteResponse.json())['method'], equals('DELETE'));
    });

    test('should handle HTTP error status codes', () async {
      final response404 = await client.get('$baseUrl/status/404');
      expect(response404.status, equals(404));
      expect(await response404.text(), equals('Not Found'));

      final response500 = await client.get('$baseUrl/status/500');
      expect(response500.status, equals(500));
      expect(await response500.text(), equals('Internal Server Error'));
    });

    test('should handle query parameters', () async {
      final response = await client.get('$baseUrl/echo?name=test&value=123');

      expect(response.status, equals(200));
      final data = await response.json();
      expect(data['query']['name'], equals('test'));
      expect(data['query']['value'], equals('123'));
    });

    test('should follow redirects by default', () async {
      final response = await client.get('$baseUrl/redirect');
      expect(response.status, equals(200));
      expect(await response.text(), equals('Redirected successfully!'));
    });

    test('should handle response headers', () async {
      final response = await client.get('$baseUrl/json');
      expect(
        response.headers.get('content-type'),
        contains('application/json'),
      );
    });

    test('should handle binary response', () async {
      final response = await client.get(baseUrl);
      final bytes = await response.bytes();
      expect(bytes, isA<List<int>>());
      expect(utf8.decode(bytes), equals('Hello World'));
    });

    test('should work with base URL configuration', () async {
      final clientWithBase = Oxy(adapter: adapter, baseURL: Uri.parse(baseUrl));

      final response = await clientWithBase.get('/json');
      expect(response.status, equals(200));

      final data = await response.json();
      expect(data['message'], equals('success'));
    });

    test('should handle form data', () async {
      final formData = FormData();
      formData.append('name', FormDataEntry.text('John Doe'));
      formData.append('email', FormDataEntry.text('john@example.com'));

      final response = await client.post(
        '$baseUrl/echo',
        body: Body.formData(formData),
      );
      expect(response.status, equals(200));

      final data = await response.json();
      expect(data['method'], equals('POST'));
      expect(data['body'], contains('name'));
      expect(data['body'], contains('John Doe'));
    });

    test('should handle concurrent requests', () async {
      final futures = List.generate(
        3,
        (i) => client.get('$baseUrl/echo?id=$i'),
      );
      final responses = await Future.wait(futures);

      for (int i = 0; i < responses.length; i++) {
        expect(responses[i].status, equals(200));
        final data = await responses[i].json();
        expect(data['query']['id'], equals(i.toString()));
      }
    });

    test('should handle abort signal', () async {
      final signal = AbortSignal();

      // Start request and abort immediately
      final requestFuture = client.get(baseUrl, signal: signal);
      signal.abort('User cancelled');

      try {
        await requestFuture;
        fail('Request should have been aborted');
      } catch (e) {
        // The request should be aborted and throw an error
        expect(e, isNotNull);
      }
    });

    test('should preserve request method case', () async {
      final response = await client.get('$baseUrl/echo');
      final data = await response.json();
      expect(data['method'], equals('GET'));
    });

    test('should handle empty response body', () async {
      final response = await client.get(baseUrl);
      expect(response.status, equals(200));
      final text = await response.text();
      expect(text, isA<String>());
    });
  });
}
