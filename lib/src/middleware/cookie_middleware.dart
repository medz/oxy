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
    await _storeResponseCookies(hydrated.url, response);
    return response;
  }

  Future<Request> _attachCookies(Request request) async {
    final cookies = await jar.load(request.url);
    if (cookies.isEmpty) {
      return request;
    }

    final cookieValue = cookies
        .map((cookie) => cookie.toRequestCookie())
        .join('; ');

    final headers = request.headers.clone();
    final existing = headers.get('cookie');
    if (existing == null || existing.isEmpty) {
      headers.set('cookie', cookieValue);
    } else {
      headers.set('cookie', '$existing; $cookieValue');
    }

    return request.copyWith(headers: headers);
  }

  Future<void> _storeResponseCookies(Uri requestUrl, Response response) async {
    final setCookies = response.headers.getSetCookie();
    if (setCookies.isEmpty) {
      return;
    }

    final parsed = <OxyCookie>[];
    for (final setCookie in setCookies) {
      try {
        parsed.add(OxyCookie.parseSetCookie(setCookie, requestUrl));
      } catch (_) {
        // Ignore malformed cookies.
      }
    }

    if (parsed.isNotEmpty) {
      await jar.save(requestUrl, parsed);
    }
  }
}
