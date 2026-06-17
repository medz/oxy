import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';
import 'cookie.dart';

final class CookieMiddleware implements Middleware {
  const CookieMiddleware(this.jar);

  final CookieJar jar;

  @override
  Future<Response> intercept(
    Request request,
    Context context,
    Next next,
  ) async {
    if (context.capability.name == 'web') {
      return next(request, context);
    }

    final hydrated = await _attachCookies(request);
    try {
      final response = await next(hydrated, context);
      await _storeResponseCookies(_cookieUri(hydrated, response), response);
      return response;
    } on StatusError catch (error) {
      await _storeResponseCookies(
        _cookieUri(hydrated, error.statusResponse),
        error.statusResponse,
      );
      rethrow;
    }
  }

  Future<Request> _attachCookies(Request request) async {
    final cookies = await jar.load(request.uri);
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

    final value = merged.entries
        .map((entry) => Cookie(entry.key, entry.value).serialize())
        .join('; ');

    return request.withHeader('cookie', value);
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
      } catch (_) {}
    }

    if (parsed.isNotEmpty) {
      await jar.save(requestUrl, parsed);
    }
  }

  Uri _cookieUri(Request request, Response response) {
    return response.url.hasScheme ? response.url : request.uri;
  }
}
