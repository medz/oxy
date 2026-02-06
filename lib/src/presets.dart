import 'cookie.dart';
import 'middleware.dart';
import 'options.dart';

class OxyPresets {
  const OxyPresets._();

  /// Builds the recommended middleware stack in official order:
  /// RequestId -> Auth? -> Cookie? -> Cache -> Logging
  static List<OxyMiddleware> standard({
    AuthMiddleware? authMiddleware,
    CookieJar? cookieJar,
    CacheStore? cacheStore,
    RequestIdProvider? requestIdProvider,
    OxyLogPrinter? logPrinter,
  }) {
    final middleware = <OxyMiddleware>[
      RequestIdMiddleware(requestIdProvider: requestIdProvider),
    ];

    if (authMiddleware != null) {
      middleware.add(authMiddleware);
    }

    if (cookieJar != null) {
      middleware.add(CookieMiddleware(cookieJar));
    }

    middleware
      ..add(CacheMiddleware(store: cacheStore))
      ..add(LoggingMiddleware(printer: logPrinter));

    return middleware;
  }
}
