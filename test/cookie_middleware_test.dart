import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('CookieMiddleware', () {
    test('attaches cookies from jar to outgoing request', () async {
      final jar = MemoryCookieJar();
      final uri = Uri.parse('https://example.com/profile');

      await jar.save(uri, [
        const Cookie('sid', '123', domain: 'example.com', path: '/'),
      ]);

      final middleware = CookieMiddleware(jar);

      late Request captured;
      await middleware.intercept(Request(uri), const RequestOptions(), (
        nextRequest,
        options,
      ) async {
        captured = nextRequest;
        return Response();
      });

      expect(captured.headers.get('cookie'), 'sid=123');
    });

    test('appends cookies when request already has cookie header', () async {
      final jar = MemoryCookieJar();
      final uri = Uri.parse('https://example.com/profile');

      await jar.save(uri, [
        const Cookie('sid', '456', domain: 'example.com', path: '/'),
      ]);

      final middleware = CookieMiddleware(jar);

      late Request captured;
      await middleware.intercept(
        Request(uri, headers: Headers({'cookie': 'trace=abc'})),
        const RequestOptions(),
        (nextRequest, options) async {
          captured = nextRequest;
          return Response();
        },
      );

      expect(captured.headers.get('cookie'), 'trace=abc; sid=456');
    });

    test('stores set-cookie response header into cookie jar', () async {
      final jar = MemoryCookieJar();
      final uri = Uri.parse('https://example.com/login');
      final middleware = CookieMiddleware(jar);

      await middleware.intercept(Request(uri), const RequestOptions(), (
        nextRequest,
        options,
      ) async {
        return Response(
          headers: Headers({
            'set-cookie': 'sid=server-token; Path=/; HttpOnly',
          }),
        );
      });

      final cookies = await jar.load(uri);
      expect(cookies, hasLength(1));
      expect(cookies.first.name, 'sid');
      expect(cookies.first.value, 'server-token');
    });

    test('ignores malformed set-cookie values', () async {
      final jar = MemoryCookieJar();
      final uri = Uri.parse('https://example.com/login');
      final middleware = CookieMiddleware(jar);

      await middleware.intercept(Request(uri), const RequestOptions(), (
        nextRequest,
        options,
      ) async {
        return Response(headers: Headers({'set-cookie': 'malformed-cookie'}));
      });

      final cookies = await jar.load(uri);
      expect(cookies, isEmpty);
    });
  });
}
