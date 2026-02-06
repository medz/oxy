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

    test('OxyConfig.withPreset appends middleware by default', () {
      final base = OxyConfig(
        middleware: <OxyMiddleware>[AuthMiddleware.staticToken('token')],
      );
      final requestId = RequestIdMiddleware(requestIdProvider: (_, _) => 'rid');

      final next = base.withPreset(<OxyMiddleware>[requestId]);

      expect(base.middleware, hasLength(1));
      expect(next.middleware, hasLength(2));
      expect(next.middleware[0], isA<AuthMiddleware>());
      expect(next.middleware[1], same(requestId));
    });

    test('OxyConfig.withPreset supports replace mode', () {
      final base = OxyConfig(
        middleware: <OxyMiddleware>[AuthMiddleware.staticToken('token')],
      );
      final requestId = RequestIdMiddleware(requestIdProvider: (_, _) => 'rid');

      final next = base.withPreset(<OxyMiddleware>[requestId], replace: true);

      expect(next.middleware, hasLength(1));
      expect(next.middleware.first, same(requestId));
    });

    test('Oxy.withPreset returns new client with merged middleware', () {
      final client = Oxy(
        OxyConfig(
          middleware: <OxyMiddleware>[AuthMiddleware.staticToken('token')],
        ),
      );
      final requestId = RequestIdMiddleware(requestIdProvider: (_, _) => 'rid');

      final next = client.withPreset(<OxyMiddleware>[requestId]);

      expect(client.config.middleware, hasLength(1));
      expect(next.config.middleware, hasLength(2));
      expect(next.config.middleware[1], same(requestId));
    });

    test('Oxy.withStandardPreset supports replace mode', () {
      final client = Oxy(
        OxyConfig(
          middleware: <OxyMiddleware>[AuthMiddleware.staticToken('token')],
        ),
      );

      final next = client.withStandardPreset(
        includeCache: false,
        includeLogging: false,
        replace: true,
      );

      expect(next.config.middleware, hasLength(1));
      expect(next.config.middleware.first, isA<RequestIdMiddleware>());
    });
  });

  group('OxyPresets.minimal/full', () {
    test('minimal builds request id only', () {
      final middleware = OxyPresets.minimal();
      expect(middleware, hasLength(1));
      expect(middleware.first, isA<RequestIdMiddleware>());
    });

    test('full always includes cookie/cache/logging', () {
      final middleware = OxyPresets.full();

      expect(middleware, hasLength(4));
      expect(middleware[0], isA<RequestIdMiddleware>());
      expect(middleware[1], isA<CookieMiddleware>());
      expect(middleware[2], isA<CacheMiddleware>());
      expect(middleware[3], isA<LoggingMiddleware>());
    });

    test('full inserts auth before cookie when provided', () {
      final middleware = OxyPresets.full(
        authMiddleware: AuthMiddleware.staticToken('token'),
      );

      expect(middleware[0], isA<RequestIdMiddleware>());
      expect(middleware[1], isA<AuthMiddleware>());
      expect(middleware[2], isA<CookieMiddleware>());
      expect(middleware[3], isA<CacheMiddleware>());
      expect(middleware[4], isA<LoggingMiddleware>());
    });

    test('withMinimalPreset replaces middleware when requested', () {
      final config = OxyConfig(
        middleware: <OxyMiddleware>[AuthMiddleware.staticToken('token')],
      );

      final next = config.withMinimalPreset(replace: true);

      expect(next.middleware, hasLength(1));
      expect(next.middleware.first, isA<RequestIdMiddleware>());
    });

    test('withFullPreset appends middleware by default', () {
      final client = Oxy(
        OxyConfig(
          middleware: <OxyMiddleware>[AuthMiddleware.staticToken('token')],
        ),
      );

      final next = client.withFullPreset();

      expect(next.config.middleware, hasLength(5));
      expect(next.config.middleware.first, isA<AuthMiddleware>());
      expect(next.config.middleware[1], isA<RequestIdMiddleware>());
      expect(next.config.middleware[2], isA<CookieMiddleware>());
      expect(next.config.middleware[3], isA<CacheMiddleware>());
      expect(next.config.middleware[4], isA<LoggingMiddleware>());
    });
  });
}
