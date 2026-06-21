import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/internal_attributes.dart';
import '../pipeline/middleware.dart';
import 'cookie.dart';

/// Adds cookie jar support for native and test transports.
///
/// Browser requests already use the browser's cookie handling, so this
/// middleware is a no-op on Web transports.
final class CookieMiddleware
    implements AttemptTransformer, AttemptResponseHandler {
  /// Creates cookie middleware backed by an `ocookie` jar.
  ///
  /// When [jar] is omitted, Oxy creates a [CookieJar] with an in-memory store.
  /// Pass [store] to plug in persistence while letting Oxy assemble the jar.
  /// If [jar] is supplied together with [store] or [policy], [jar] wins; debug
  /// assertions report the redundant configuration during development.
  CookieMiddleware({CookieJar? jar, CookieStore? store, CookiePolicy? policy})
    : assert(
        jar == null || (store == null && policy == null),
        'When jar is provided, store and policy are ignored.',
      ),
      jar =
          jar ??
          CookieJar(store: store, policy: policy ?? const CookiePolicy());

  /// Cookie storage used by the middleware.
  final CookieJar jar;

  @override
  Future<Request> onAttempt(Request request, Context context) {
    if (context.capability.name == 'web') {
      return Future.value(request);
    }

    return _attachCookies(request);
  }

  @override
  Future<Response> onAttemptResponse(
    Request request,
    Response response,
    Context context,
  ) async {
    if (context.capability.name != 'web') {
      await _storeResponseCookies(_cookieUri(request, response), response);
    }
    return response;
  }

  Future<Request> _attachCookies(Request request) async {
    final managed =
        request.attributes.get(cookieHeaderManagedAttribute) == true;

    final existing = request.headers.get('cookie');
    final hasExplicitCookie =
        !managed && existing != null && existing.isNotEmpty;
    if (!hasExplicitCookie) {
      final header = await jar.header(request.uri);
      if (header != null && header.isNotEmpty) {
        final hydrated = request.withHeader('cookie', header);
        return hydrated.copyWith(
          attributes: hydrated.attributes.set(
            cookieHeaderManagedAttribute,
            true,
          ),
        );
      }

      if (managed) {
        final headers = request.headers.copy()..delete('cookie');
        return request.copyWith(
          headers: headers,
          attributes: request.attributes.remove(cookieHeaderManagedAttribute),
        );
      }
      return request;
    }

    final explicitCookies = Cookie.parse(
      existing,
    ).entries.map((entry) => Cookie(entry.key, entry.value)).toList();
    final explicitNames = {for (final cookie in explicitCookies) cookie.name};
    final jarCookies = (await jar.load(
      request.uri,
    )).where((cookie) => !explicitNames.contains(cookie.name));
    final headerCookies = <Cookie>[...explicitCookies, ...jarCookies];

    if (headerCookies.isEmpty) {
      return request;
    }

    final value = headerCookies.map(_toRequestCookie).join('; ');

    final hydrated = request.withHeader('cookie', value);
    return hydrated.copyWith(
      attributes: hasExplicitCookie
          ? hydrated.attributes.remove(cookieHeaderManagedAttribute)
          : hydrated.attributes.set(cookieHeaderManagedAttribute, true),
    );
  }

  Future<void> _storeResponseCookies(Uri requestUrl, Response response) async {
    final setCookies = response.headers.getSetCookie();
    if (setCookies.isEmpty) {
      return;
    }

    for (final setCookie in setCookies) {
      try {
        await jar.save(requestUrl, [setCookie]);
      } on FormatException catch (_) {
      } on ArgumentError catch (_) {}
    }
  }

  Uri _cookieUri(Request request, Response response) {
    return response.url.hasScheme ? response.url : request.uri;
  }

  String _toRequestCookie(Cookie cookie) {
    return Cookie(cookie.name, cookie.value).serialize();
  }
}
