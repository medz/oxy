import 'package:ht/ht.dart';

import '../_internal/request_utils.dart';
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

    final cookieValue = cookies
        .map((cookie) => cookie.toRequestCookie())
        .join('; ');

    final headers = cloneHeaders(request.headers);
    final existing = headers.get('cookie');
    if (existing == null || existing.isEmpty) {
      headers.set('cookie', cookieValue);
    } else {
      headers.set('cookie', '$existing; $cookieValue');
    }

    return copyRequest(request, headers: headers);
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
