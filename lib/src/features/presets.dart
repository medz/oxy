import '../pipeline/middleware.dart';
import 'cache.dart';
import 'cookie.dart';
import 'cookie_middleware.dart';
import 'logging.dart';
import 'request_id.dart';
import 'auth.dart';

final class Presets {
  const Presets._();

  static List<Middleware> minimal({RequestIdMiddleware? requestId}) {
    return <Middleware>[requestId ?? RequestIdMiddleware()];
  }

  static List<Middleware> standard({
    bool includeRequestId = true,
    AuthMiddleware? auth,
    CookieJar? cookieJar,
    bool includeCache = false,
    CacheMiddleware? cache,
    bool includeLogging = false,
    LoggingMiddleware? logging,
  }) {
    return <Middleware>[
      if (includeRequestId) RequestIdMiddleware(),
      if (auth != null) auth,
      if (cookieJar != null) CookieMiddleware(cookieJar),
      if (includeCache) cache ?? CacheMiddleware(),
      if (includeLogging) logging ?? LoggingMiddleware(),
    ];
  }

  static List<Middleware> full({
    AuthMiddleware? auth,
    CookieJar? cookieJar,
    CacheMiddleware? cache,
    LoggingMiddleware? logging,
  }) {
    return <Middleware>[
      RequestIdMiddleware(),
      if (auth != null) auth,
      CookieMiddleware(cookieJar ?? MemoryCookieJar()),
      cache ?? CacheMiddleware(),
      logging ?? LoggingMiddleware(),
    ];
  }
}
