import 'dart:async';
import 'dart:typed_data';

import '../_internal/body/body.native.dart';
import '../abort/abort.dart';
import '../headers.dart';
import 'enums.dart';

/// Web standards compliant request.
///
/// E.g:
/// ```dart
/// final request = Request("https://example.com");
/// ```
class Request implements Body {
  Request(
    this.url, {
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
       signal = signal ?? AbortSignal();

  final Body _body;
  final String url;

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
  final Headers headers;

  /// Returns the cache policy of the request.
  final RequestCache cache;

  @override
  bool get bodyUsed => _body.bodyUsed;

  /// Returns the request stream body.
  @override
  Stream<Uint8List> get body => _body.body;

  @override
  Request clone() {
    return Request(
      url,
      body: _body.clone(),
      cache: cache,
      method: method,
      headers: headers,
      priority: priority,
      redirect: redirect,
      referrer: referrer,
      referrerPolicy: referrerPolicy,
      signal: signal.aborted ? AbortSignal() : signal,
      integrity: integrity,
      keepalive: keepalive,
      mode: mode,
    );
  }

  @override
  Future<Uint8List> bytes() => _body.bytes();

  @override
  Future json() => _body.json();

  @override
  Future<String> text() => _body.text();
}
