import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';
import 'package:test/test.dart';

final class CapabilityTransport implements Transport {
  CapabilityTransport(this.capability, this._responder);

  @override
  final PlatformCapability capability;

  final Future<Response> Function(Request request, Context context) _responder;

  @override
  Future<void> close() async {}

  @override
  Future<Response> send(Request request, Context context) {
    return _responder(request, context);
  }
}

void main() {
  test('auth and request id middleware modify immutable requests', () async {
    late Request captured;
    final client = Client(
      ClientOptions(
        transport: MockTransport((request, context) async {
          captured = request;
          return Response.text('ok');
        }),
        middleware: [
          AuthMiddleware.staticToken('abc'),
          RequestIdMiddleware(requestIdProvider: (_, _) => 'rid'),
        ],
      ),
    );

    await client.get('https://example.com');

    expect(captured.headers.get('authorization'), 'Bearer abc');
    expect(captured.headers.get('x-request-id'), 'rid');
  });

  test('cookie middleware isolates cookie state in client-owned jar', () async {
    final jar = MemoryCookieJar();
    var calls = 0;
    late Request secondRequest;
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 2) {
            secondRequest = request;
          }
          return Response.text(
            'ok',
            headers: calls == 1
                ? Headers({'set-cookie': 'sid=abc; Path=/; HttpOnly'})
                : null,
          );
        }),
      ),
    );

    await client.get('https://example.com/login');
    await client.get('https://example.com/profile');

    expect(secondRequest.headers.get('cookie'), 'sid=abc');
    expect(
      await jar.load(Uri.parse('https://sub.example.com/profile')),
      isEmpty,
    );
  });

  test('cookie jar enforces domain and host-only scoping', () async {
    final jar = MemoryCookieJar();
    await jar.save(Uri.parse('https://example.com/login'), [
      const Cookie('sid', 'host', path: '/'),
    ]);
    await jar.save(Uri.parse('https://api.example.com/login'), [
      const Cookie('wide', 'domain', domain: 'example.com', path: '/'),
    ]);

    final rootCookies = await jar.load(Uri.parse('https://example.com/home'));
    final subdomainCookies = await jar.load(
      Uri.parse('https://sub.example.com/home'),
    );

    expect(rootCookies.map((cookie) => cookie.name), contains('sid'));
    expect(
      subdomainCookies.map((cookie) => cookie.name),
      isNot(contains('sid')),
    );
    expect(subdomainCookies.map((cookie) => cookie.name), contains('wide'));
    await expectLater(
      jar.save(Uri.parse('https://evil.example/login'), [
        const Cookie('attack', '1', domain: 'victim.example', path: '/'),
      ]),
      throwsArgumentError,
    );
  });

  test('cookie middleware stores response cookies against final URL', () async {
    final jar = MemoryCookieJar();
    var calls = 0;
    late Request finalHostRequest;
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            return Response.text(
              'redirected',
              headers: Headers({'set-cookie': 'sid=final; Path=/'}),
              url: Uri.parse('https://b.example.com/final'),
            );
          }
          finalHostRequest = request;
          return Response.text('ok');
        }),
      ),
    );

    await client.get('https://a.example.com/start');
    await client.get('https://b.example.com/account');

    expect(finalHostRequest.headers.get('cookie'), 'sid=final');
    expect(await jar.load(Uri.parse('https://a.example.com/account')), isEmpty);
  });

  test('cookie middleware is a no-op for browser transports', () async {
    final jar = MemoryCookieJar();
    await jar.save(Uri.parse('https://example.com'), [
      const Cookie('sid', 'abc', path: '/'),
    ]);
    late Request captured;
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: CapabilityTransport(PlatformCapability.web, (
          request,
          context,
        ) async {
          captured = request;
          return Response.text(
            'ok',
            headers: Headers({'set-cookie': 'ignored=1'}),
          );
        }),
      ),
    );

    await client.get('https://example.com');

    expect(captured.headers.has('cookie'), isFalse);
    expect(await jar.load(Uri.parse('https://example.com')), hasLength(1));
  });

  test('cache middleware reuses fresh buffered responses', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text(
            'v$calls',
            headers: Headers({'cache-control': 'max-age=60'}),
          );
        }),
      ),
    );

    final first = await client.get('https://example.com/feed');
    final second = await client.get('https://example.com/feed');

    expect(await first.text(), 'v1');
    expect(await second.text(), 'v1');
    expect(second.fromCache, isTrue);
    expect(calls, 1);
  });

  test('cache middleware keys request header variants', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text(
            request.headers.get('authorization') ?? 'none',
            headers: Headers({
              'cache-control': 'max-age=60',
              'vary': 'Authorization',
            }),
          );
        }),
      ),
    );

    final first = await client.get(
      'https://example.com/me',
      headers: {'authorization': 'Bearer a'},
    );
    final second = await client.get(
      'https://example.com/me',
      headers: {'authorization': 'Bearer b'},
    );

    expect(await first.text(), 'Bearer a');
    expect(await second.text(), 'Bearer b');
    expect(calls, 2);
  });

  test('cache middleware revalidates request and response no-cache', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (request.headers.get('if-none-match') == 'v1') {
            return Response(null, status: 304, headers: {'etag': 'v1'});
          }
          return Response.text(
            'fresh',
            headers: Headers({
              'cache-control': 'no-cache, max-age=60',
              'etag': 'v1',
            }),
          );
        }),
      ),
    );

    expect(
      await (await client.get('https://example.com/feed')).text(),
      'fresh',
    );
    final second = await client.get(
      'https://example.com/feed',
      headers: {'cache-control': 'max-age=0'},
    );

    expect(await second.text(), 'fresh');
    expect(second.fromCache, isTrue);
    expect(calls, 2);
  });

  test(
    'cache middleware skips oversized entries without failing response',
    () async {
      final large = List.filled(32, 'x').join();
      var calls = 0;
      final client = Client(
        ClientOptions(
          middleware: [CacheMiddleware(maxEntryBytes: 8)],
          transport: MockTransport((request, context) async {
            calls += 1;
            return Response.stream(
              Stream<List<int>>.value(large.codeUnits),
              headers: Headers({'cache-control': 'max-age=60'}),
            );
          }),
        ),
      );

      final response = await client.get('https://example.com/large');

      expect(await response.text(), large);
      expect(response.fromCache, isFalse);
      expect(calls, 1);
    },
  );

  test('presets remain single-package feature composition', () {
    final middleware = Presets.full(auth: AuthMiddleware.staticToken('token'));

    expect(middleware[0], isA<RequestIdMiddleware>());
    expect(middleware[1], isA<AuthMiddleware>());
    expect(middleware[2], isA<CookieMiddleware>());
    expect(middleware[3], isA<CacheMiddleware>());
    expect(middleware[4], isA<LoggingMiddleware>());
  });
}
