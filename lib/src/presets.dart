import 'cookie.dart';
import 'middleware.dart';
import 'options.dart';

class OxyPresets {
  const OxyPresets._();

  /// Builds the recommended middleware stack in official order:
  /// RequestId -> Auth? -> Cookie? -> Cache -> Logging
  static List<OxyMiddleware> standard({
    bool includeRequestId = true,
    AuthMiddleware? authMiddleware,
    CookieMiddleware? cookieMiddleware,
    CookieJar? cookieJar,
    bool includeCache = true,
    CacheMiddleware? cacheMiddleware,
    CacheStore? cacheStore,
    bool includeLogging = true,
    LoggingMiddleware? loggingMiddleware,
    RequestIdProvider? requestIdProvider,
    RequestIdMiddleware? requestIdMiddleware,
    OxyLogPrinter? logPrinter,
  }) {
    final middleware = <OxyMiddleware>[];

    if (includeRequestId) {
      middleware.add(
        requestIdMiddleware ??
            RequestIdMiddleware(requestIdProvider: requestIdProvider),
      );
    }

    if (authMiddleware != null) {
      middleware.add(authMiddleware);
    }

    final resolvedCookieMiddleware =
        cookieMiddleware ??
        (cookieJar == null ? null : CookieMiddleware(cookieJar));
    if (resolvedCookieMiddleware != null) {
      middleware.add(resolvedCookieMiddleware);
    }

    if (includeCache) {
      middleware.add(cacheMiddleware ?? CacheMiddleware(store: cacheStore));
    }

    if (includeLogging) {
      middleware.add(
        loggingMiddleware ?? LoggingMiddleware(printer: logPrinter),
      );
    }

    return middleware;
  }
}
