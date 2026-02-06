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
  return _normalizeCookie(ocookie.Cookie.fromString(setCookie), requestUri);
}

extension OxyCookieExtension on ocookie.Cookie {
  bool isExpired(DateTime nowUtc) {
    final normalizedNow = nowUtc.toUtc();

    if (maxAge != null && maxAge == Duration.zero) {
      return true;
    }

    if (expires != null && !expires!.isAfter(normalizedNow)) {
      return true;
    }

    return false;
  }

  bool matchesUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final normalizedDomain = _cookieDomain(this, uri);

    final domainMatches =
        host == normalizedDomain || host.endsWith('.$normalizedDomain');
    if (!domainMatches) {
      return false;
    }

    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    final cookiePath = _cookiePath(this, uri);
    if (!requestPath.startsWith(cookiePath)) {
      return false;
    }

    if ((secure ?? false) && uri.scheme != 'https') {
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

class MemoryCookieJar implements CookieJar {
  final List<ocookie.Cookie> _cookies = <ocookie.Cookie>[];

  @override
  Future<void> clear() async {
    _cookies.clear();
  }

  @override
  Future<List<ocookie.Cookie>> load(Uri uri) async {
    final now = DateTime.now().toUtc();
    _cookies.removeWhere((cookie) => cookie.isExpired(now));

    return _cookies
        .where((cookie) => cookie.matchesUri(uri))
        .toList(growable: false);
  }

  @override
  Future<void> save(Uri uri, List<ocookie.Cookie> cookies) async {
    final now = DateTime.now().toUtc();
    _cookies.removeWhere((cookie) => cookie.isExpired(now));

    for (final cookie in cookies) {
      final normalized = _normalizeCookie(cookie, uri);
      _cookies.removeWhere((item) {
        return item.name == normalized.name &&
            _cookieDomain(item, uri) == _cookieDomain(normalized, uri) &&
            _cookiePath(item, uri) == _cookiePath(normalized, uri);
      });

      if (!normalized.isExpired(now)) {
        _cookies.add(normalized);
      }
    }
  }
}

ocookie.Cookie _normalizeCookie(ocookie.Cookie cookie, Uri uri) {
  final maxAge = cookie.maxAge == null
      ? null
      : Duration(seconds: max(cookie.maxAge!.inSeconds, 0));

  return cookie.copyWith(
    domain: _cookieDomain(cookie, uri),
    path: _cookiePath(cookie, uri),
    maxAge: maxAge,
    expires: cookie.expires?.toUtc(),
  );
}

String _cookieDomain(ocookie.Cookie cookie, Uri uri) {
  final value = (cookie.domain ?? uri.host).toLowerCase();
  return value.startsWith('.') ? value.substring(1) : value;
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
