import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';
import 'package:test/test.dart';

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

  test('presets remain single-package feature composition', () {
    final middleware = Presets.full(auth: AuthMiddleware.staticToken('token'));

    expect(middleware[0], isA<RequestIdMiddleware>());
    expect(middleware[1], isA<AuthMiddleware>());
    expect(middleware[2], isA<CookieMiddleware>());
    expect(middleware[3], isA<CacheMiddleware>());
    expect(middleware[4], isA<LoggingMiddleware>());
  });
}
