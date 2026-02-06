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
  });
}
