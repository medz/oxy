import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../body/body.web.dart' show Body;
import '../headers/headers.web.dart' show Headers;
import '../url/url.web.dart' show URL;
import 'cache.dart' show RequestCache;
import 'credentials.dart' show RequestCredentials;
import 'mode.dart' show RequestMode;
import 'redirect.dart' show RequestRedirect;

extension type RequestInfo._(JSAny _) implements JSAny {
  factory RequestInfo(Request request) => RequestInfo._(request);
  factory RequestInfo.string(String url) => RequestInfo._(url.toJS);
  factory RequestInfo.url(URL url) => RequestInfo._(url);
}

@JS("Request")
extension type Request._(Body _) implements Body {
  @JS("constructor")
  external factory Request._internal(RequestInfo input, [JSObject? init]);

  factory Request(
    RequestInfo input, {
    String method = "GET",
    Headers? headers,
    Body? body,
    RequestMode mode = RequestMode.cors,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
    RequestCache cache = RequestCache.default_,
    RequestRedirect redirect = RequestRedirect.follow,
    String? referrer,
    String? integrity,
    bool? keepalive,
  }) {
    final init = JSObject()
      ..setProperty("method".toJS, method.toJS)
      ..setProperty("mode".toJS, mode.value.toJS)
      ..setProperty("credentials".toJS, credentials.value.toJS)
      ..setProperty("cache".toJS, cache.value.toJS)
      ..setProperty("redirect".toJS, redirect.name.toJS);

    if (headers != null) init.setProperty("headers".toJS, headers);
    if (body != null) init.setProperty("body".toJS, body);
    if (referrer != null) init.setProperty("referrer".toJS, referrer.toJS);
    if (integrity != null) init.setProperty("integrity".toJS, integrity.toJS);
    if (keepalive != null) init.setProperty("keepalive".toJS, keepalive.toJS);

    return Request._internal(input, init);
  }

  external String get destination;
  external Headers get headers;
  external String get integrity;
  external bool get keepalive;
  external String get method;
  external String get referrer;
  external String get referrerPolicy;
  external String get url;

  external Request clone();

  @JS("cache")
  external JSString get _cache;
  RequestCache get cache => RequestCache.parse(_cache.toDart);

  @JS("credentials")
  external JSString get _credentials;
  RequestCredentials get credentials =>
      RequestCredentials.parse(_credentials.toDart);

  @JS("mode")
  external JSString get _mode;
  RequestMode get mode => RequestMode.parse(_mode.toDart);

  @JS("redirect")
  external JSString get _redirect;
  RequestRedirect get redirect => RequestRedirect.parse(_redirect.toDart);
}
