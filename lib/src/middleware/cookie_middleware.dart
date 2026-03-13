import 'package:ht/ht.dart';

import '../cookie.dart';
import '../options.dart';

class CookieMiddleware implements OxyMiddleware {
  const CookieMiddleware(this.jar);

  final CookieJar jar;

  @override
  Future<Response> intercept(
    Request request,
    RequestOptions options,
    Next next,
  ) async {
    final hydrated = await _attachCookies(request);
    final response = await next(hydrated, options);
    await _storeResponseCookies(Uri.parse(hydrated.url), response);
    return response;
  }

  Future<Request> _attachCookies(Request request) async {
    final cookies = await jar.load(Uri.parse(request.url));
    if (cookies.isEmpty) {
      return request;
    }

    final merged = <String, String>{
      for (final cookie in cookies) cookie.name: cookie.value,
    };
    final existing = request.headers.get('cookie');
    if (existing != null && existing.isNotEmpty) {
      merged.addAll(Cookie.parse(existing));
    }

    request.headers.set(
      'cookie',
      merged.entries
          .map((entry) => Cookie(entry.key, entry.value).serialize())
          .join('; '),
    );

    return request;
  }

  Future<void> _storeResponseCookies(Uri requestUrl, Response response) async {
    final setCookies = response.headers.getSetCookie();
    if (setCookies.isEmpty) {
      return;
    }

    final parsed = <Cookie>[];
    for (final setCookie in setCookies) {
      try {
        parsed.add(parseSetCookie(setCookie, requestUrl));
      } catch (_) {
        // Ignore malformed cookies.
      }
    }

    if (parsed.isNotEmpty) {
      await jar.save(requestUrl, parsed);
    }
  }
}
