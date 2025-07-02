import 'dart:async';
import 'dart:typed_data';

import 'abort.dart';
import 'body.dart';
import 'formdata.dart';
import 'headers.dart';
import 'request_common.dart';

class AdapterRequest extends FormDataHelper implements Body {
  AdapterRequest({
    String method = "GET",
    Headers? headers,
    Body? body,
    AbortSignal? signal,
    this.cache = RequestCache.defaults,
    this.integrity = "",
    this.keepalive = false,
    this.mode = RequestMode.cors,
    this.priority = RequestPriority.auto,
    this.redirect = RequestRedirect.follow,
    this.referrer = "about:client",
    this.referrerPolicy = ReferrerPolicy.empty,
    this.credentials = RequestCredentials.sameOrigin,
  }) : _body = body ?? Body(Stream.empty()),
       method = method.toUpperCase(),
       headers = headers ?? Headers(),
       signal = signal ?? AbortController().signal {
    for (final (name, value) in _body.headers.entries()) {
      this.headers.set(name, value);
    }
  }

  final Body _body;

  final AbortSignal signal;
  final String integrity;
  final bool keepalive;
  final RequestMode mode;
  final RequestPriority priority;
  final RequestRedirect redirect;
  final String referrer;
  final ReferrerPolicy referrerPolicy;
  final RequestCredentials credentials;

  /// The request method.
  final String method;

  /// Returns the headers of the request.
  @override
  final Headers headers;

  /// Returns the cache policy of the request.
  final RequestCache cache;

  @override
  bool get bodyUsed => _body.bodyUsed;

  /// Returns the request stream body.
  @override
  Stream<Uint8List> get body => _body.body;

  @override
  Future<Uint8List> bytes() => _body.bytes();

  @override
  Future json() => _body.json();

  @override
  Future<String> text() => _body.text();

  @override
  AdapterRequest clone() {
    return AdapterRequest(
      body: _body.clone(),
      cache: cache,
      method: method,
      headers: headers,
      priority: priority,
      redirect: redirect,
      referrer: referrer,
      referrerPolicy: referrerPolicy,
      signal: signal,
      integrity: integrity,
      keepalive: keepalive,
      mode: mode,
      credentials: credentials,
    );
  }
}
