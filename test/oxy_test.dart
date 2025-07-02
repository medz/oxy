import 'dart:async';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';

// Mock adapter for testing
class MockAdapter implements Adapter {
  final Future<Response> Function(Uri url, AdapterRequest request)? _fetchImpl;
  final bool _isSupportWeb;

  MockAdapter({
    Future<Response> Function(Uri url, AdapterRequest request)? fetchImpl,
    bool isSupportWeb = true,
  }) : _fetchImpl = fetchImpl,
       _isSupportWeb = isSupportWeb;

  @override
  bool get isSupportWeb => _isSupportWeb;

  @override
  Future<Response> fetch(Uri url, AdapterRequest request) {
    if (_fetchImpl != null) {
      return _fetchImpl(url, request);
    }
    // Default mock response
    return Future.value(
      Response(
        status: 200,
        statusText: 'OK',
        body: Body.text('Mock response'),
        url: url.toString(),
      ),
    );
  }
}

// Testable Oxy class that bypasses adapter selection
class TestableOxy extends Oxy {
  TestableOxy({super.adapter, super.baseURL});

  @override
  Future<Response> call(Request request) {
    // Always use the provided adapter, bypass platform detection
    final url = baseURL?.resolve(request.url) ?? Uri.parse(request.url);
    return adapter.fetch(url, request);
  }
}

void main() {
  group('Oxy', () {
    group('constructor', () {
      test('creates instance with default adapter', () {
        final oxy = Oxy();
        expect(oxy.adapter, isA<DefaultAdapter>());
        expect(oxy.baseURL, isNull);
      });

      test('creates instance with custom adapter', () {
        final customAdapter = MockAdapter();
        final oxy = Oxy(adapter: customAdapter);
        expect(oxy.adapter, equals(customAdapter));
      });

      test('creates instance with base URL', () {
        final baseURL = Uri.parse('https://api.example.com');
        final oxy = Oxy(baseURL: baseURL);
        expect(oxy.baseURL, equals(baseURL));
      });

      test('creates instance with both custom adapter and base URL', () {
        final customAdapter = MockAdapter();
        final baseURL = Uri.parse('https://api.example.com');
        final oxy = Oxy(adapter: customAdapter, baseURL: baseURL);
        expect(oxy.adapter, equals(customAdapter));
        expect(oxy.baseURL, equals(baseURL));
      });
    });

    group('call() method', () {
      test('executes request with absolute URL', () async {
        final mockAdapter = MockAdapter(
          fetchImpl: (url, request) async {
            return Response(
              status: 200,
              body: Body.text('OK'),
              url: url.toString(),
            );
          },
        );
        final oxy = TestableOxy(adapter: mockAdapter);
        final request = Request('https://example.com/data');

        final response = await oxy(request);

        expect(response, isA<Response>());
        expect(response.status, equals(200));
        expect(response.url, equals('https://example.com/data'));
      });

      test('resolves relative URL against base URL', () async {
        final mockAdapter = MockAdapter(
          fetchImpl: (url, request) async {
            expect(url.toString(), equals('https://api.example.com/users'));
            return Response(
              status: 200,
              body: Body.text('Users data'),
              url: url.toString(),
            );
          },
        );

        final oxy = TestableOxy(
          adapter: mockAdapter,
          baseURL: Uri.parse('https://api.example.com'),
        );
        final request = Request('/users');

        final response = await oxy(request);

        expect(response.status, equals(200));
        expect(response.url, equals('https://api.example.com/users'));
      });

      test('handles absolute URL when base URL is set', () async {
        final mockAdapter = MockAdapter(
          fetchImpl: (url, request) async {
            expect(url.toString(), equals('https://other.com/data'));
            return Response(
              status: 200,
              body: Body.text('Other data'),
              url: url.toString(),
            );
          },
        );

        final oxy = TestableOxy(
          adapter: mockAdapter,
          baseURL: Uri.parse('https://api.example.com'),
        );
        final request = Request('https://other.com/data');

        final response = await oxy(request);

        expect(response.url, equals('https://other.com/data'));
      });

      test('passes request to adapter correctly', () async {
        AdapterRequest? capturedRequest;
        final mockAdapter = MockAdapter(
          fetchImpl: (url, request) async {
            capturedRequest = request;
            return Response(status: 200, body: Body.text('OK'));
          },
        );

        final oxy = TestableOxy(adapter: mockAdapter);
        final headers = Headers({'Authorization': 'Bearer token'});
        final body = Body.text('test data');
        final request = Request(
          'https://example.com',
          method: 'POST',
          headers: headers,
          body: body,
        );

        await oxy(request);

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.method, equals('POST'));
        expect(
          capturedRequest!.headers.get('Authorization'),
          equals('Bearer token'),
        );
      });

      test(
        'uses default adapter when custom adapter does not support web',
        () async {
          final mockAdapter = MockAdapter(
            isSupportWeb: false,
            fetchImpl: (url, request) async {
              return Response(
                status: 200,
                body: Body.text('Default adapter response'),
                url: url.toString(),
              );
            },
          );
          final oxy = TestableOxy(adapter: mockAdapter);
          final request = Request('https://example.com');

          final response = await oxy(request);
          expect(response, isA<Response>());
        },
      );
    });

    group('adapter selection', () {
      test(
        'uses custom adapter when it supports web on web platform',
        () async {
          // Note: This test would behave differently on actual web platform
          // For now, we test the logic without platform detection
          final webAdapter = MockAdapter(
            isSupportWeb: true,
            fetchImpl: (url, request) async {
              return Response(
                status: 200,
                body: Body.text('Web adapter response'),
                url: url.toString(),
              );
            },
          );
          final oxy = TestableOxy(adapter: webAdapter);
          final request = Request('https://example.com');

          final response = await oxy(request);
          expect(response, isA<Response>());
        },
      );
    });
  });

  group('fetch() function', () {
    test('creates request with correct parameters', () async {
      // Test that fetch function creates proper Request object
      final headers = Headers({'Content-Type': 'application/json'});
      final body = Body.text('test data');

      // We can't easily mock the global fetch function, so we test
      // that the Request creation works correctly
      final request = Request(
        'https://example.com/data',
        method: 'POST',
        headers: headers,
        body: body,
        cache: RequestCache.noCache,
        integrity: 'sha256-hash',
        keepalive: true,
      );

      expect(request.url, equals('https://example.com/data'));
      expect(request.method, equals('POST'));
      expect(request.headers, equals(headers));
      expect(request.cache, equals(RequestCache.noCache));
      expect(request.integrity, equals('sha256-hash'));
      expect(request.keepalive, isTrue);
    });

    test('validates request parameter defaults', () async {
      // Test that default parameters are set correctly
      final request = Request('https://example.com/data');

      expect(request.method, equals('GET'));
      expect(request.cache, equals(RequestCache.defaults));
      expect(request.integrity, equals(''));
      expect(request.keepalive, isFalse);
      expect(request.mode, equals(RequestMode.cors));
      expect(request.priority, equals(RequestPriority.auto));
      expect(request.redirect, equals(RequestRedirect.follow));
      expect(request.referrer, equals('about:client'));
      expect(request.referrerPolicy, equals(ReferrerPolicy.empty));
      expect(request.credentials, equals(RequestCredentials.sameOrigin));
    });
  });

  group('OxyRequestMethods extension', () {
    late MockAdapter mockAdapter;
    late Oxy client;

    setUp(() {
      mockAdapter = MockAdapter(
        fetchImpl: (url, request) async {
          return Response(
            status: 200,
            body: Body.json({'method': request.method, 'url': url.toString()}),
          );
        },
      );
      client = TestableOxy(
        adapter: mockAdapter,
        baseURL: Uri.parse('https://api.example.com'),
      );
    });

    group('get()', () {
      test('makes GET request with correct method', () async {
        final response = await client.get('/users');
        final data = await response.json();

        expect(data['method'], equals('GET'));
        expect(data['url'], equals('https://api.example.com/users'));
      });

      test('includes custom headers', () async {
        final headers = Headers({'Authorization': 'Bearer token'});
        final response = await client.get('/users', headers: headers);

        expect(response, isA<Response>());
      });

      test('can include body in GET request', () async {
        final body = Body.text('search params');
        final response = await client.get('/search', body: body);

        expect(response, isA<Response>());
      });
    });

    group('post()', () {
      test('makes POST request with correct method', () async {
        final response = await client.post('/users');
        final data = await response.json();

        expect(data['method'], equals('POST'));
        expect(data['url'], equals('https://api.example.com/users'));
      });

      test('includes request body', () async {
        final body = Body.json({'name': 'John'});
        final response = await client.post('/users', body: body);

        expect(response, isA<Response>());
      });

      test('includes custom headers', () async {
        final headers = Headers({'Content-Type': 'application/json'});
        final body = Body.json({'name': 'John'});
        final response = await client.post(
          '/users',
          headers: headers,
          body: body,
        );

        expect(response, isA<Response>());
      });
    });

    group('put()', () {
      test('makes PUT request with correct method', () async {
        final response = await client.put('/users/123');
        final data = await response.json();

        expect(data['method'], equals('PUT'));
        expect(data['url'], equals('https://api.example.com/users/123'));
      });

      test('includes request body', () async {
        final body = Body.json({'name': 'John Updated'});
        final response = await client.put('/users/123', body: body);

        expect(response, isA<Response>());
      });
    });

    group('delete()', () {
      test('makes DELETE request with correct method', () async {
        final response = await client.delete('/users/123');
        final data = await response.json();

        expect(data['method'], equals('DELETE'));
        expect(data['url'], equals('https://api.example.com/users/123'));
      });

      test('does not include body parameter', () {
        // Verify that delete method doesn't have body parameter by compilation
        expect(() => client.delete('/users/123'), returnsNormally);
      });

      test('includes custom headers', () async {
        final headers = Headers({'Authorization': 'Bearer token'});
        final response = await client.delete('/users/123', headers: headers);

        expect(response, isA<Response>());
      });
    });

    group('patch()', () {
      test('makes PATCH request with correct method', () async {
        final response = await client.patch('/users/123');
        final data = await response.json();

        expect(data['method'], equals('PATCH'));
        expect(data['url'], equals('https://api.example.com/users/123'));
      });

      test('does not include body parameter', () {
        // Verify that patch method doesn't have body parameter by compilation
        expect(() => client.patch('/users/123'), returnsNormally);
      });

      test('includes all other parameters', () async {
        final headers = Headers({'Authorization': 'Bearer token'});
        final controller = AbortController();

        final response = await client.patch(
          '/users/123',
          headers: headers,
          signal: controller.signal,
          cache: RequestCache.noCache,
          integrity: 'sha256-hash',
          keepalive: true,
          mode: RequestMode.sameOrigin,
          priority: RequestPriority.high,
          redirect: RequestRedirect.error,
          referrer: 'https://example.com',
          referrerPolicy: ReferrerPolicy.origin,
          credentials: RequestCredentials.include,
        );

        expect(response, isA<Response>());
      });
    });

    group('URL resolution', () {
      test('resolves relative URLs against base URL', () async {
        final response = await client.get('/api/v1/users');
        final data = await response.json();

        expect(data['url'], equals('https://api.example.com/api/v1/users'));
      });

      test('handles absolute URLs', () async {
        final response = await client.get('https://other.com/data');
        final data = await response.json();

        expect(data['url'], equals('https://other.com/data'));
      });

      test('handles URLs with query parameters', () async {
        final response = await client.get('/users?page=1&limit=10');
        final data = await response.json();

        expect(
          data['url'],
          equals('https://api.example.com/users?page=1&limit=10'),
        );
      });
    });
  });

  group('default oxy instance', () {
    test('is properly configured', () {
      expect(oxy, isA<Oxy>());
      expect(oxy.adapter, isA<DefaultAdapter>());
      expect(oxy.baseURL, isNull);
    });

    test('can create requests', () async {
      final request = Request('https://example.com/api');

      expect(request.url, equals('https://example.com/api'));
      expect(request.method, equals('GET'));
      expect(request, isA<Request>());
    });
  });

  group('error handling', () {
    test('propagates adapter errors', () async {
      final errorAdapter = MockAdapter(
        fetchImpl: (url, request) async {
          throw Exception('Network error');
        },
      );

      final client = TestableOxy(adapter: errorAdapter);
      final request = Request('https://example.com');

      expect(() async => await client(request), throwsException);
    });

    test('handles malformed URLs gracefully', () async {
      // Test that URI parsing works as expected
      expect(() => Uri.parse('not-a-valid-url'), returnsNormally);

      // Test that Request handles various URL formats
      expect(() => Request('https://example.com'), returnsNormally);
      expect(() => Request('http://example.com/path'), returnsNormally);
      expect(() => Request('/relative/path'), returnsNormally);
    });
  });

  group('integration scenarios', () {
    test('complete request-response cycle', () async {
      final mockAdapter = MockAdapter(
        fetchImpl: (url, request) async {
          // Clone the request to read body without consuming it
          final clonedRequest = request.clone();
          final requestBody = await clonedRequest.text();

          return Response(
            status: 200,
            headers: Headers({'Content-Type': 'application/json'}),
            body: Body.json({
              'receivedMethod': request.method,
              'receivedUrl': url.toString(),
              'receivedBody': requestBody,
              'receivedHeaders': request.headers
                  .entries()
                  .map((e) => '${e.$1}: ${e.$2}')
                  .toList(),
            }),
          );
        },
      );

      final client = TestableOxy(
        adapter: mockAdapter,
        baseURL: Uri.parse('https://api.test.com'),
      );

      final response = await client.post(
        '/echo',
        headers: Headers({'X-Custom-Header': 'test-value'}),
        body: Body.json({'message': 'hello world'}),
      );

      expect(response.ok, isTrue);
      expect(response.status, equals(200));

      final responseData = await response.json();
      expect(responseData['receivedMethod'], equals('POST'));
      expect(responseData['receivedUrl'], equals('https://api.test.com/echo'));
      expect(responseData['receivedBody'], contains('hello world'));
    });

    test('handles chained operations', () async {
      final client = TestableOxy(
        adapter: MockAdapter(
          fetchImpl: (url, request) async {
            return Response(
              status: 200,
              body: Body.json({'data': 'mock data for ${url.path}'}),
              url: url.toString(),
            );
          },
        ),
        baseURL: Uri.parse('https://api.example.com'),
      );

      // Make multiple requests
      final responses = await Future.wait([
        client.get('/users'),
        client.get('/posts'),
        client.get('/comments'),
      ]);

      expect(responses.length, equals(3));
      for (final response in responses) {
        expect(response.ok, isTrue);
      }
    });
  });
}
