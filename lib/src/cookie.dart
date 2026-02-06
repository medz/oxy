import 'dart:math';

import 'package:ocookie/ocookie.dart' as ocookie;

enum OxyCookieSameSite { lax, strict, none, unspecified }

class OxyCookie {
  const OxyCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expires,
    this.maxAge,
    this.httpOnly = false,
    this.secure = false,
    this.sameSite = OxyCookieSameSite.unspecified,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expires;
  final Duration? maxAge;
  final bool httpOnly;
  final bool secure;
  final OxyCookieSameSite sameSite;

  factory OxyCookie.parseSetCookie(String setCookie, Uri uri) {
    final parsed = ocookie.Cookie.fromString(setCookie);

    final domain = parsed.domain?.toLowerCase() ?? uri.host.toLowerCase();
    final path = parsed.path ?? _defaultPath(uri.path);
    final maxAge = parsed.maxAge == null
        ? null
        : Duration(seconds: max(parsed.maxAge!.inSeconds, 0));
    final sameSite = switch (parsed.sameSite) {
      ocookie.CookieSameSite.strict => OxyCookieSameSite.strict,
      ocookie.CookieSameSite.none => OxyCookieSameSite.none,
      ocookie.CookieSameSite.lax => OxyCookieSameSite.lax,
      null => OxyCookieSameSite.unspecified,
    };

    return OxyCookie(
      name: parsed.name,
      value: parsed.value,
      domain: _normalizeDomain(domain),
      path: path,
      expires: parsed.expires?.toUtc(),
      maxAge: maxAge,
      httpOnly: parsed.httpOnly ?? false,
      secure: parsed.secure ?? false,
      sameSite: sameSite,
    );
  }

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

  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final normalizedDomain = _normalizeDomain(domain);

    final domainMatches =
        host == normalizedDomain || host.endsWith('.$normalizedDomain');
    if (!domainMatches) {
      return false;
    }

    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    if (!requestPath.startsWith(path)) {
      return false;
    }

    if (secure && uri.scheme != 'https') {
      return false;
    }

    return true;
  }

  String toRequestCookie() => ocookie.Cookie(name, value).serialize();

  static String _normalizeDomain(String value) {
    return value.startsWith('.') ? value.substring(1) : value;
  }

  static String _defaultPath(String requestPath) {
    if (requestPath.isEmpty || !requestPath.startsWith('/')) {
      return '/';
    }

    final slashIndex = requestPath.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '/';
    }

    return requestPath.substring(0, slashIndex);
  }
}

abstract interface class CookieJar {
  Future<List<OxyCookie>> load(Uri uri);
  Future<void> save(Uri uri, List<OxyCookie> cookies);
  Future<void> clear();
}

class MemoryCookieJar implements CookieJar {
  final List<OxyCookie> _cookies = <OxyCookie>[];

  @override
  Future<void> clear() async {
    _cookies.clear();
  }

  @override
  Future<List<OxyCookie>> load(Uri uri) async {
    final now = DateTime.now().toUtc();
    _cookies.removeWhere((cookie) => cookie.isExpired(now));

    return _cookies
        .where((cookie) => cookie.matches(uri))
        .toList(growable: false);
  }

  @override
  Future<void> save(Uri uri, List<OxyCookie> cookies) async {
    final now = DateTime.now().toUtc();
    _cookies.removeWhere((cookie) => cookie.isExpired(now));

    for (final cookie in cookies) {
      _cookies.removeWhere((item) {
        return item.name == cookie.name &&
            item.domain == cookie.domain &&
            item.path == cookie.path;
      });

      if (!cookie.isExpired(now)) {
        _cookies.add(cookie);
      }
    }
  }
}
