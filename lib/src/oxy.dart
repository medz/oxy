import 'abort.dart';
import 'body.dart';
import 'adapter.dart';
import 'default_adapter.dart';
import 'headers.dart';
import 'request.dart';
import 'request_common.dart';
import 'response.dart';

import '_internal/is_web_platform.native.dart'
    if (dart.library.js_interop) '_internal/is_web_platform.web.dart';

class Oxy {
  Oxy({this.adapter = const DefaultAdapter(), this.baseURL});

  final Adapter adapter;
  final Uri? baseURL;

  Future<Response> call(Request request) {
    final adapter = this.adapter.isSupportWeb && isWebPlatform
        ? this.adapter
        : const DefaultAdapter();
    final url = baseURL?.resolve(request.url) ?? Uri.parse(request.url);

    return adapter.fetch(url, request);
  }
}

extension OxyRequestMethods on Oxy {
  Future<Response> get(
    String url, {
    Headers? headers,
    Body? body,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    return call(
      Request(
        url,
        method: "GET",
        headers: headers,
        body: body,
        signal: signal,
        cache: cache,
        integrity: integrity,
        keepalive: keepalive,
        mode: mode,
        priority: priority,
        redirect: redirect,
        referrer: referrer,
        referrerPolicy: referrerPolicy,
        credentials: credentials,
      ),
    );
  }

  Future<Response> post(
    String url, {
    Headers? headers,
    Body? body,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    return call(
      Request(
        url,
        method: "POST",
        headers: headers,
        body: body,
        signal: signal,
        cache: cache,
        integrity: integrity,
        keepalive: keepalive,
        mode: mode,
        priority: priority,
        redirect: redirect,
        referrer: referrer,
        referrerPolicy: referrerPolicy,
        credentials: credentials,
      ),
    );
  }

  Future<Response> put(
    String url, {
    Headers? headers,
    Body? body,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    return call(
      Request(
        url,
        method: "PUT",
        headers: headers,
        body: body,
        signal: signal,
        cache: cache,
        integrity: integrity,
        keepalive: keepalive,
        mode: mode,
        priority: priority,
        redirect: redirect,
        referrer: referrer,
        referrerPolicy: referrerPolicy,
        credentials: credentials,
      ),
    );
  }

  Future<Response> delete(
    String url, {
    Headers? headers,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    return call(
      Request(
        url,
        method: "DELETE",
        headers: headers,
        signal: signal,
        cache: cache,
        integrity: integrity,
        keepalive: keepalive,
        mode: mode,
        priority: priority,
        redirect: redirect,
        referrer: referrer,
        referrerPolicy: referrerPolicy,
        credentials: credentials,
      ),
    );
  }

  Future<Response> patch(
    String url, {
    Headers? headers,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    return call(
      Request(
        url,
        method: "PATCH",
        headers: headers,
        signal: signal,
        cache: cache,
        integrity: integrity,
        keepalive: keepalive,
        mode: mode,
        priority: priority,
        redirect: redirect,
        referrer: referrer,
        referrerPolicy: referrerPolicy,
        credentials: credentials,
      ),
    );
  }
}
