import 'dart:async';
import 'dart:typed_data';

import 'abort/abort.dart';
import 'body.dart';
import 'headers.dart';

/// Request cache policy.
enum RequestCache {
  /// Default cache policy.
  defaults,

  /// No cache policy.
  noStore,

  /// Reload cache policy.
  reload,

  /// No cache policy.
  noCache,

  /// Force cache policy.
  forceCache,

  /// Only if cached policy.
  onlyIfCached;

  /// Returns the [value] of the request cache policy.
  ///
  /// > [!NOTE]
  /// > If the [value] is not recognized, it returns [defaults].
  static RequestCache lookup(String value) {
    return switch (value) {
      'default' => defaults,
      'no-store' => noStore,
      'reload' => reload,
      'no-cache' => noCache,
      'force-cache' => forceCache,
      'only-if-cached' => onlyIfCached,
      _ => defaults,
    };
  }

  @override
  String toString() {
    return switch (this) {
      defaults => 'default',
      noStore => 'no-store',
      reload => 'reload',
      noCache => 'no-cache',
      forceCache => 'force-cache',
      onlyIfCached => 'only-if-cached',
    };
  }
}

/// The request credentials policy.
enum RequestCredentials {
  /// Never send credentials in the request or include credentials in the response.
  omit,

  /// Only send and include credentials for same-origin requests. This is the default.
  sameOrigin,

  /// Always include credentials, even for cross-origin requests.
  include;

  /// Returns the string representation of the request credentials policy.
  static RequestCredentials lookup(String value) {
    return switch (value) {
      'omit' => omit,
      'same-origin' => sameOrigin,
      'include' => include,
      _ => sameOrigin,
    };
  }

  @override
  String toString() {
    return switch (this) {
      omit => 'omit',
      sameOrigin => 'same-origin',
      include => 'include',
    };
  }
}

enum RequestMode {
  cors,
  noCors,
  sameOrigin,
  navigate;

  static RequestMode lookup(String value) {
    return switch (value) {
      'cors' => cors,
      'no-cors' => noCors,
      'same-origin' => sameOrigin,
      'navigate' => navigate,
      _ => sameOrigin,
    };
  }

  @override
  String toString() {
    return switch (this) {
      cors => 'cors',
      noCors => 'no-cors',
      sameOrigin => 'same-origin',
      navigate => 'navigate',
    };
  }
}

enum RequestPriority {
  auto,
  low,
  high;

  static RequestPriority lookup(String value) {
    return switch (value) {
      'auto' => auto,
      'low' => low,
      'high' => high,

      _ => auto,
    };
  }

  @override
  String toString() => name;
}

enum RequestRedirect {
  follow,
  error,
  manual;

  static RequestRedirect lookup(String value) {
    return switch (value) {
      'follow' => follow,
      'error' => error,
      'manual' => manual,

      _ => follow,
    };
  }

  @override
  String toString() => name;
}

enum ReferrerPolicy {
  noReferrer,
  noReferrerWhenDowngrade,
  origin,
  originWhenCrossOrigin,
  sameOrigin,
  strictOrigin,
  strictOriginWhenCrossOrigin,
  unsafeUrl;

  static ReferrerPolicy? lookup(String value) {
    return switch (value) {
      'no-referrer' => noReferrer,
      'no-referrer-when-downgrade' => noReferrerWhenDowngrade,
      'origin' => origin,
      'origin-when-cross-origin' => originWhenCrossOrigin,
      'same-origin' => sameOrigin,
      'strict-origin' => strictOrigin,
      'strict-origin-when-cross-origin' => strictOriginWhenCrossOrigin,
      'unsafe-url' => unsafeUrl,
      _ => null,
    };
  }

  @override
  String toString() {
    return switch (this) {
      noReferrer => 'no-referrer',
      noReferrerWhenDowngrade => 'no-referrer-when-downgrade',
      origin => 'origin',
      originWhenCrossOrigin => 'origin-when-cross-origin',
      sameOrigin => 'same-origin',
      strictOrigin => 'strict-origin',
      strictOriginWhenCrossOrigin => 'strict-origin-when-cross-origin',
      unsafeUrl => 'unsafe-url',
    };
  }
}

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
    this.referrerPolicy,
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
  final ReferrerPolicy? referrerPolicy;
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
