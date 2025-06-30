import 'abort.dart';
import 'body.dart';
import 'dirver.dart';
import 'headers.dart';
import 'request.dart';

class Oxy {
  Oxy({required this.dirver});

  final Dirver dirver;

  Future call(Request request) => dirver.request(request);
}

extension OxyRequestMethods on Oxy {
  Future get(
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

  Future post(
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

  Future put(
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

  Future delete(
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

  Future patch(
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
