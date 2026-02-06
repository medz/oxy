import 'dart:async';
import 'dart:convert';

import 'package:ht/ht.dart';

import 'options.dart';

import '_internal/is_web_platform.native.dart'
    if (dart.library.js_interop) '_internal/is_web_platform.web.dart';
import '_internal/transport.stub.dart'
    if (dart.library.io) '_internal/transport.native.dart'
    if (dart.library.js_interop) '_internal/transport.web.dart'
    as transport;

class Oxy {
  Oxy({this.baseURL, Headers? defaultHeaders, this.userAgent = 'oxy/0.1.0'})
    : defaultHeaders = defaultHeaders?.clone() ?? Headers();

  final Uri? baseURL;
  final Headers defaultHeaders;
  final String userAgent;

  Future<Response> call(
    Request request, {
    FetchOptions options = const FetchOptions(),
  }) {
    options.signal?.throwIfAborted();

    final mergedHeaders = _mergeHeaders(request.headers);
    if (!isWebPlatform &&
        !mergedHeaders.has('user-agent') &&
        userAgent.isNotEmpty) {
      mergedHeaders.set('user-agent', userAgent);
    }

    final resolvedRequest = request.copyWith(
      url: _resolveUrl(request.url),
      headers: mergedHeaders,
    );

    Future<Response> future = transport.fetchTransport(
      resolvedRequest,
      options,
    );
    if (options.timeout != null) {
      future = future.timeout(
        options.timeout!,
        onTimeout: () {
          final timeout = TimeoutException(
            'Request timeout after ${options.timeout}',
            options.timeout,
          );
          options.signal?.abort(timeout);
          throw timeout;
        },
      );
    }

    return future;
  }

  Future<Response> request(
    String url, {
    String method = 'GET',
    Headers? headers,
    Object? body,
    Object? json,
    FetchOptions options = const FetchOptions(),
  }) {
    final requestHeaders = headers?.clone() ?? Headers();
    final requestBody = _normalizeBody(
      body: body,
      json: json,
      headers: requestHeaders,
    );

    final request = Request(
      Uri.parse(url),
      method: method,
      headers: requestHeaders,
      body: requestBody,
    );

    return call(request, options: options);
  }

  Future<Response> get(
    String url, {
    Headers? headers,
    FetchOptions options = const FetchOptions(),
  }) {
    return request(url, method: 'GET', headers: headers, options: options);
  }

  Future<Response> post(
    String url, {
    Headers? headers,
    Object? body,
    Object? json,
    FetchOptions options = const FetchOptions(),
  }) {
    return request(
      url,
      method: 'POST',
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
  }

  Future<Response> put(
    String url, {
    Headers? headers,
    Object? body,
    Object? json,
    FetchOptions options = const FetchOptions(),
  }) {
    return request(
      url,
      method: 'PUT',
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
  }

  Future<Response> patch(
    String url, {
    Headers? headers,
    Object? body,
    Object? json,
    FetchOptions options = const FetchOptions(),
  }) {
    return request(
      url,
      method: 'PATCH',
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
  }

  Future<Response> delete(
    String url, {
    Headers? headers,
    Object? body,
    Object? json,
    FetchOptions options = const FetchOptions(),
  }) {
    return request(
      url,
      method: 'DELETE',
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
  }

  Future<Response> head(
    String url, {
    Headers? headers,
    FetchOptions options = const FetchOptions(),
  }) {
    return request(url, method: 'HEAD', headers: headers, options: options);
  }

  Future<Response> options(
    String url, {
    Headers? headers,
    Object? body,
    Object? json,
    FetchOptions options = const FetchOptions(),
  }) {
    return request(
      url,
      method: 'OPTIONS',
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
  }

  Uri _resolveUrl(Uri url) {
    if (url.hasScheme) {
      return url;
    }

    if (baseURL != null) {
      return baseURL!.resolveUri(url);
    }

    throw ArgumentError.value(
      url.toString(),
      'request.url',
      'Relative URLs require Oxy(baseURL: ...).',
    );
  }

  Headers _mergeHeaders(Headers requestHeaders) {
    final merged = defaultHeaders.clone();

    for (final name in requestHeaders.names()) {
      merged.delete(name);
      for (final value in requestHeaders.getAll(name)) {
        merged.append(name, value);
      }
    }

    return merged;
  }

  static Object? _normalizeBody({
    required Object? body,
    required Object? json,
    required Headers headers,
  }) {
    if (body != null && json != null) {
      throw ArgumentError('Use either body or json, not both.');
    }

    if (json != null) {
      if (!headers.has('content-type')) {
        headers.set('content-type', 'application/json; charset=utf-8');
      }
      return jsonEncode(json);
    }

    return body;
  }
}

final Oxy oxy = Oxy();

Future<Response> fetch(
  String url, {
  String method = 'GET',
  Headers? headers,
  Object? body,
  Object? json,
  FetchOptions options = const FetchOptions(),
}) {
  return oxy.request(
    url,
    method: method,
    headers: headers,
    body: body,
    json: json,
    options: options,
  );
}
