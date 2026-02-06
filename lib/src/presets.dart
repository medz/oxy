import 'cookie.dart';
import 'middleware.dart';
import 'options.dart';
import 'oxy.dart';

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

extension OxyConfigPresetExtension on OxyConfig {
  OxyConfig withPreset(List<OxyMiddleware> preset, {bool replace = false}) {
    final middleware = replace
        ? List<OxyMiddleware>.from(preset)
        : <OxyMiddleware>[...this.middleware, ...preset];
    return copyWith(middleware: middleware);
  }

  OxyConfig withStandardPreset({
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
    bool replace = false,
  }) {
    return withPreset(
      OxyPresets.standard(
        includeRequestId: includeRequestId,
        authMiddleware: authMiddleware,
        cookieMiddleware: cookieMiddleware,
        cookieJar: cookieJar,
        includeCache: includeCache,
        cacheMiddleware: cacheMiddleware,
        cacheStore: cacheStore,
        includeLogging: includeLogging,
        loggingMiddleware: loggingMiddleware,
        requestIdProvider: requestIdProvider,
        requestIdMiddleware: requestIdMiddleware,
        logPrinter: logPrinter,
      ),
      replace: replace,
    );
  }
}

extension OxyPresetExtension on Oxy {
  Oxy withPreset(List<OxyMiddleware> preset, {bool replace = false}) {
    return Oxy(config.withPreset(preset, replace: replace));
  }

  Oxy withStandardPreset({
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
    bool replace = false,
  }) {
    return Oxy(
      config.withStandardPreset(
        includeRequestId: includeRequestId,
        authMiddleware: authMiddleware,
        cookieMiddleware: cookieMiddleware,
        cookieJar: cookieJar,
        includeCache: includeCache,
        cacheMiddleware: cacheMiddleware,
        cacheStore: cacheStore,
        includeLogging: includeLogging,
        loggingMiddleware: loggingMiddleware,
        requestIdProvider: requestIdProvider,
        requestIdMiddleware: requestIdMiddleware,
        logPrinter: logPrinter,
        replace: replace,
      ),
    );
  }
}
