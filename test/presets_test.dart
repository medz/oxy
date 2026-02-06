import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('OxyPresets.standard', () {
    test('builds default official middleware order', () {
      final middleware = OxyPresets.standard();

      expect(middleware, hasLength(3));
      expect(middleware[0], isA<RequestIdMiddleware>());
      expect(middleware[1], isA<CacheMiddleware>());
      expect(middleware[2], isA<LoggingMiddleware>());
    });

    test('inserts auth and cookie in official order when provided', () {
      final middleware = OxyPresets.standard(
        authMiddleware: AuthMiddleware.staticToken('token'),
        cookieJar: MemoryCookieJar(),
      );

      expect(middleware, hasLength(5));
      expect(middleware[0], isA<RequestIdMiddleware>());
      expect(middleware[1], isA<AuthMiddleware>());
      expect(middleware[2], isA<CookieMiddleware>());
      expect(middleware[3], isA<CacheMiddleware>());
      expect(middleware[4], isA<LoggingMiddleware>());
    });

    test('supports disabling built-in optional middlewares', () {
      final middleware = OxyPresets.standard(
        includeRequestId: false,
        includeCache: false,
        includeLogging: false,
        authMiddleware: AuthMiddleware.staticToken('token'),
        cookieJar: MemoryCookieJar(),
      );

      expect(middleware, hasLength(2));
      expect(middleware[0], isA<AuthMiddleware>());
      expect(middleware[1], isA<CookieMiddleware>());
    });

    test('supports overriding request id/cache/logging middlewares', () {
      final requestId = RequestIdMiddleware(requestIdProvider: (_, _) => 'rid');
      final cache = CacheMiddleware(store: MemoryCacheStore());
      final logging = LoggingMiddleware(printer: (_) {});

      final middleware = OxyPresets.standard(
        requestIdMiddleware: requestId,
        cacheMiddleware: cache,
        loggingMiddleware: logging,
      );

      expect(middleware[0], same(requestId));
      expect(middleware[1], same(cache));
      expect(middleware[2], same(logging));
    });

    test('uses explicit cookie middleware before cache', () {
      final customCookie = CookieMiddleware(MemoryCookieJar());
      final middleware = OxyPresets.standard(
        cookieMiddleware: customCookie,
        cookieJar: MemoryCookieJar(),
      );

      expect(middleware[1], same(customCookie));
      expect(middleware[2], isA<CacheMiddleware>());
    });
  });
}
