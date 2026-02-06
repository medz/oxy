import 'dart:math';

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
    final segments = setCookie
        .split(';')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    if (segments.isEmpty || !segments.first.contains('=')) {
      throw ArgumentError.value(setCookie, 'setCookie', 'Invalid Set-Cookie');
    }

    final first = segments.first;
    final equalsIndex = first.indexOf('=');
    final name = first.substring(0, equalsIndex).trim();
    final value = first.substring(equalsIndex + 1).trim();

    var domain = uri.host.toLowerCase();
    var path = _defaultPath(uri.path);
    DateTime? expires;
    Duration? maxAge;
    var secure = false;
    var httpOnly = false;
    var sameSite = OxyCookieSameSite.unspecified;

    for (var i = 1; i < segments.length; i++) {
      final part = segments[i];
      final attrIndex = part.indexOf('=');
      final key = (attrIndex == -1 ? part : part.substring(0, attrIndex))
          .trim()
          .toLowerCase();
      final attrValue = attrIndex == -1
          ? ''
          : part.substring(attrIndex + 1).trim();

      switch (key) {
        case 'domain':
          if (attrValue.isNotEmpty) {
            domain = attrValue.toLowerCase();
          }
        case 'path':
          if (attrValue.isNotEmpty) {
            path = attrValue;
          }
        case 'expires':
          expires = DateTime.tryParse(attrValue)?.toUtc();
        case 'max-age':
          final seconds = int.tryParse(attrValue);
          if (seconds != null) {
            maxAge = Duration(seconds: max(seconds, 0));
          }
        case 'secure':
          secure = true;
        case 'httponly':
          httpOnly = true;
        case 'samesite':
          sameSite = switch (attrValue.toLowerCase()) {
            'strict' => OxyCookieSameSite.strict,
            'none' => OxyCookieSameSite.none,
            'lax' => OxyCookieSameSite.lax,
            _ => OxyCookieSameSite.unspecified,
          };
      }
    }

    return OxyCookie(
      name: name,
      value: value,
      domain: _normalizeDomain(domain),
      path: path,
      expires: expires,
      maxAge: maxAge,
      httpOnly: httpOnly,
      secure: secure,
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

  String toRequestCookie() => '$name=$value';

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
