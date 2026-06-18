import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/internal_attributes.dart';
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
    final managed =
        request.attributes.get(cookieHeaderManagedAttribute) == true;
    final cookies = await jar.load(request.uri);
    if (cookies.isEmpty) {
      if (managed) {
        final headers = request.headers.copy()..delete('cookie');
        return request.copyWith(
          headers: headers,
          attributes: request.attributes.remove(cookieHeaderManagedAttribute),
        );
      }
      return request;
    }

    final existing = request.headers.get('cookie');
    final hasExplicitCookie =
        !managed && existing != null && existing.isNotEmpty;
    final explicitCookies = hasExplicitCookie
        ? Cookie.parse(
            existing,
          ).entries.map((entry) => Cookie(entry.key, entry.value)).toList()
        : const <Cookie>[];
    final explicitNames = {for (final cookie in explicitCookies) cookie.name};
    final jarCookies =
        cookies.where((cookie) => !explicitNames.contains(cookie.name)).toList()
          ..sort(_cookieHeaderOrder);
    final headerCookies = <Cookie>[...explicitCookies, ...jarCookies];

    if (headerCookies.isEmpty) {
      return request;
    }

    final value = headerCookies
        .map((cookie) => cookie.toRequestCookie())
        .join('; ');

    final hydrated = request.withHeader('cookie', value);
    return hydrated.copyWith(
      attributes: hasExplicitCookie
          ? hydrated.attributes.remove(cookieHeaderManagedAttribute)
          : hydrated.attributes.set(cookieHeaderManagedAttribute, true),
    );
  }

  int _cookieHeaderOrder(Cookie a, Cookie b) {
    final pathOrder = (b.path?.length ?? 0).compareTo(a.path?.length ?? 0);
    if (pathOrder != 0) {
      return pathOrder;
    }
    return 0;
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
      } on FormatException catch (_) {
      } on ArgumentError catch (_) {}
    }

    if (parsed.isNotEmpty) {
      await jar.save(requestUrl, parsed);
    }
  }

  Uri _cookieUri(Request request, Response response) {
    return response.url.hasScheme ? response.url : request.uri;
  }
}
