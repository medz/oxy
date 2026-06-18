import 'dart:math';

import 'package:ocookie/ocookie.dart' as ocookie;

export 'package:ocookie/ocookie.dart'
    show
        Cookie,
        CookieCodec,
        CookieNullableField,
        CookiePriority,
        CookieSameSite;

ocookie.Cookie parseSetCookie(String setCookie, Uri requestUri) {
  final normalized = _normalizeCookie(
    ocookie.Cookie.fromString(setCookie),
    requestUri,
  );
  if (!normalized.hostOnly) {
    return normalized.cookie;
  }
  return normalized.cookie.copyWith(
    clear: const <ocookie.CookieNullableField>{
      ocookie.CookieNullableField.domain,
    },
  );
}

extension CookieRequestExtension on ocookie.Cookie {
  bool isExpired(DateTime nowUtc) {
    final now = nowUtc.toUtc();
    if (maxAge != null && maxAge == Duration.zero) {
      return true;
    }
    if (expires != null && !expires!.isAfter(now)) {
      return true;
    }
    return false;
  }

  bool matchesUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final domain = _cookieDomain(this, uri.host);
    if (host != domain && !host.endsWith('.$domain')) {
      return false;
    }

    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    final cookiePath = _cookiePath(this, uri);
    if (requestPath != cookiePath &&
        !(requestPath.startsWith(cookiePath) &&
            (cookiePath.endsWith('/') ||
                requestPath[cookiePath.length] == '/'))) {
      return false;
    }

    if (secure && uri.scheme != 'https') {
      return false;
    }
    return true;
  }

  String toRequestCookie() => ocookie.Cookie(name, value).serialize();
}

abstract interface class CookieJar {
  Future<List<ocookie.Cookie>> load(Uri uri);
  Future<void> save(Uri uri, List<ocookie.Cookie> cookies);
  Future<void> clear();
}

final class MemoryCookieJar implements CookieJar {
  final List<_StoredCookie> _cookies = <_StoredCookie>[];

  @override
  Future<void> clear() async {
    _cookies.clear();
  }

  @override
  Future<List<ocookie.Cookie>> load(Uri uri) async {
    final now = DateTime.now().toUtc();
    _cookies.removeWhere((cookie) => cookie.cookie.isExpired(now));
    return _cookies
        .where((cookie) => cookie.matchesUri(uri))
        .map((cookie) => cookie.cookie)
        .toList();
  }

  @override
  Future<void> save(Uri uri, List<ocookie.Cookie> cookies) async {
    final now = DateTime.now().toUtc();
    _cookies.removeWhere((cookie) => cookie.cookie.isExpired(now));

    for (final cookie in cookies) {
      final normalized = _normalizeCookie(cookie, uri);
      _cookies.removeWhere((item) {
        return item.cookie.name == normalized.cookie.name &&
            item.domain == normalized.domain &&
            item.path == normalized.path;
      });

      if (!normalized.cookie.isExpired(now)) {
        _cookies.add(normalized);
      }
    }
  }
}

final class _StoredCookie {
  const _StoredCookie({
    required this.cookie,
    required this.domain,
    required this.path,
    required this.hostOnly,
  });

  final ocookie.Cookie cookie;
  final String domain;
  final String path;
  final bool hostOnly;

  bool matchesUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (hostOnly) {
      if (host != domain) {
        return false;
      }
    } else if (host != domain && !host.endsWith('.$domain')) {
      return false;
    }

    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    if (requestPath != path &&
        !(requestPath.startsWith(path) &&
            (path.endsWith('/') || requestPath[path.length] == '/'))) {
      return false;
    }

    if (cookie.secure && uri.scheme != 'https') {
      return false;
    }
    return true;
  }
}

_StoredCookie _normalizeCookie(ocookie.Cookie cookie, Uri uri) {
  final now = DateTime.now().toUtc();
  final maxAge = cookie.maxAge == null
      ? null
      : Duration(seconds: max(cookie.maxAge!.inSeconds, 0));
  final expires = switch (maxAge) {
    null => cookie.expires?.toUtc(),
    Duration.zero => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    _ => now.add(maxAge),
  };
  final host = uri.host.toLowerCase();
  final rawDomain = cookie.domain?.trim();
  final hostOnly = rawDomain == null || rawDomain.isEmpty;
  final domain = hostOnly ? host : _normalizeDomain(rawDomain);
  if (!hostOnly &&
      (!_domainMatches(host, domain) || !_isCookieDomain(domain))) {
    throw ArgumentError.value(
      cookie.domain,
      'cookie.domain',
      'Cookie domain does not match request host.',
    );
  }
  final path = _cookiePath(cookie, uri);

  return _StoredCookie(
    cookie: cookie.copyWith(
      domain: domain,
      path: path,
      maxAge: maxAge,
      expires: expires,
    ),
    domain: domain,
    path: path,
    hostOnly: hostOnly,
  );
}

String _cookieDomain(ocookie.Cookie cookie, String fallbackHost) {
  final value = (cookie.domain ?? fallbackHost).toLowerCase();
  return _normalizeDomain(value);
}

String _normalizeDomain(String value) {
  final trimmed = value.trim().toLowerCase();
  return trimmed.startsWith('.') ? trimmed.substring(1) : trimmed;
}

bool _domainMatches(String host, String domain) {
  return host == domain || host.endsWith('.$domain');
}

bool _isCookieDomain(String domain) {
  return domain.contains('.') && !_ipv4Pattern.hasMatch(domain);
}

String _cookiePath(ocookie.Cookie cookie, Uri uri) {
  return cookie.path ?? _defaultPath(uri.path);
}

String _defaultPath(String requestPath) {
  if (requestPath.isEmpty || !requestPath.startsWith('/')) {
    return '/';
  }
  final slashIndex = requestPath.lastIndexOf('/');
  if (slashIndex <= 0) {
    return '/';
  }
  return requestPath.substring(0, slashIndex);
}

final RegExp _ipv4Pattern = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');
