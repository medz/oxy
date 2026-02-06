import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ht/ht.dart';

import 'decode.dart';
import 'errors.dart';
import 'options.dart';
import 'result.dart';

import '_internal/is_web_platform.native.dart'
    if (dart.library.js_interop) '_internal/is_web_platform.web.dart';
import '_internal/transport.stub.dart'
    if (dart.library.io) '_internal/transport.native.dart'
    if (dart.library.js_interop) '_internal/transport.web.dart'
    as transport;

class Oxy {
  Oxy([OxyConfig? config]) : _config = config ?? const OxyConfig();

  final OxyConfig _config;
  static final Random _random = Random.secure();

  OxyConfig get config => _config;

  Oxy withConfig(OxyConfig patch) => Oxy(patch);

  Oxy withMiddleware(List<OxyMiddleware> middleware) {
    return Oxy(
      _config.copyWith(
        middleware: <OxyMiddleware>[..._config.middleware, ...middleware],
      ),
    );
  }

  Future<Response> call(Request request, {RequestOptions? options}) {
    return send(request, options: options);
  }

  Future<Response> send(Request request, {RequestOptions? options}) async {
    final resolvedOptions = _resolveOptions(options);
    final signal = resolvedOptions.signal;
    if (signal?.aborted ?? false) {
      throw OxyCancelledException(reason: signal?.reason);
    }

    final resolvedRequest = _prepareRequest(request, resolvedOptions);
    final response = await _sendWithRetry(resolvedRequest, resolvedOptions);

    if (resolvedOptions.redirectPolicy == RedirectPolicy.error &&
        response.redirected) {
      throw OxyHttpException(
        response,
        message: 'Redirect blocked by RedirectPolicy.error',
      );
    }

    if (resolvedOptions.httpErrorPolicy == HttpErrorPolicy.throwException &&
        !response.ok) {
      throw OxyHttpException(response);
    }

    return response;
  }

  Future<OxyResult<Response>> safeSend(
    Request request, {
    RequestOptions? options,
  }) {
    return _capture(() => send(request, options: options));
  }

  Future<Response> request(
    String method,
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    final requestHeaders = headers?.clone() ?? Headers();
    final requestBody = _normalizeBody(
      body: body,
      json: json,
      headers: requestHeaders,
    );

    final nextOptions = (options ?? const RequestOptions()).copyWith(
      query: query,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return send(
      Request(
        Uri.parse(path),
        method: method,
        headers: requestHeaders,
        body: requestBody,
      ),
      options: nextOptions,
    );
  }

  Future<OxyResult<Response>> safeRequest(
    String method,
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return _capture(
      () => request(
        method,
        path,
        query: query,
        headers: headers,
        body: body,
        json: json,
        options: options,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
    );
  }

  Future<T> requestDecoded<T>(
    String method,
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) async {
    final response = await request(
      method,
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
    return response.decode<T>(decoder: decoder);
  }

  Future<OxyResult<T>> safeRequestDecoded<T>(
    String method,
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return _capture(
      () => requestDecoded<T>(
        method,
        path,
        query: query,
        headers: headers,
        body: body,
        json: json,
        options: options,
        decoder: decoder,
      ),
    );
  }

  Future<Response> get(
    String path, {
    QueryMap? query,
    Headers? headers,
    RequestOptions? options,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'GET',
      path,
      query: query,
      headers: headers,
      options: options,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<OxyResult<Response>> safeGet(
    String path, {
    QueryMap? query,
    Headers? headers,
    RequestOptions? options,
    ProgressCallback? onReceiveProgress,
  }) {
    return safeRequest(
      'GET',
      path,
      query: query,
      headers: headers,
      options: options,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<T> getDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return requestDecoded<T>(
      'GET',
      path,
      query: query,
      headers: headers,
      options: options,
      decoder: decoder,
    );
  }

  Future<OxyResult<T>> safeGetDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return safeRequestDecoded<T>(
      'GET',
      path,
      query: query,
      headers: headers,
      options: options,
      decoder: decoder,
    );
  }

  Future<Response> post(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'POST',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<OxyResult<Response>> safePost(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return safeRequest(
      'POST',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<T> postDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return requestDecoded<T>(
      'POST',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<OxyResult<T>> safePostDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return safeRequestDecoded<T>(
      'POST',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<Response> put(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'PUT',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<OxyResult<Response>> safePut(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return safeRequest(
      'PUT',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<T> putDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return requestDecoded<T>(
      'PUT',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<OxyResult<T>> safePutDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return safeRequestDecoded<T>(
      'PUT',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<Response> patch(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'PATCH',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<OxyResult<Response>> safePatch(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return safeRequest(
      'PATCH',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<T> patchDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return requestDecoded<T>(
      'PATCH',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<OxyResult<T>> safePatchDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return safeRequestDecoded<T>(
      'PATCH',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<Response> delete(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'DELETE',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<OxyResult<Response>> safeDelete(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return safeRequest(
      'DELETE',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<T> deleteDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return requestDecoded<T>(
      'DELETE',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<OxyResult<T>> safeDeleteDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return safeRequestDecoded<T>(
      'DELETE',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<Response> head(
    String path, {
    QueryMap? query,
    Headers? headers,
    RequestOptions? options,
  }) {
    return request(
      'HEAD',
      path,
      query: query,
      headers: headers,
      options: options,
    );
  }

  Future<OxyResult<Response>> safeHead(
    String path, {
    QueryMap? query,
    Headers? headers,
    RequestOptions? options,
  }) {
    return safeRequest(
      'HEAD',
      path,
      query: query,
      headers: headers,
      options: options,
    );
  }

  Future<Response> options(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
  }) {
    return request(
      'OPTIONS',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
  }

  Future<OxyResult<Response>> safeOptions(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
  }) {
    return safeRequest(
      'OPTIONS',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
  }

  Future<T> optionsDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return requestDecoded<T>(
      'OPTIONS',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<OxyResult<T>> safeOptionsDecoded<T>(
    String path, {
    QueryMap? query,
    Headers? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) {
    return safeRequestDecoded<T>(
      'OPTIONS',
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
      decoder: decoder,
    );
  }

  Future<OxyResult<T>> _capture<T>(Future<T> Function() action) async {
    try {
      final value = await action();
      return OxySuccess<T>(value);
    } catch (error, trace) {
      return OxyFailure<T>(error, trace);
    }
  }

  RequestOptions _resolveOptions(RequestOptions? options) {
    final incoming = options ?? const RequestOptions();
    final middleware = <OxyMiddleware>[..._config.middleware];
    middleware.addAll(incoming.middleware);

    return RequestOptions(
      headers: incoming.headers?.clone(),
      query: incoming.query,
      connectTimeout: incoming.connectTimeout ?? _config.connectTimeout,
      requestTimeout: incoming.requestTimeout ?? _config.requestTimeout,
      signal: incoming.signal,
      redirectPolicy: incoming.redirectPolicy ?? _config.redirectPolicy,
      maxRedirects: incoming.maxRedirects ?? _config.maxRedirects,
      keepAlive: incoming.keepAlive ?? _config.keepAlive,
      retryPolicy: incoming.retryPolicy ?? _config.retryPolicy,
      httpErrorPolicy: incoming.httpErrorPolicy ?? _config.httpErrorPolicy,
      middleware: middleware,
      onSendProgress: incoming.onSendProgress,
      onReceiveProgress: incoming.onReceiveProgress,
      extra: incoming.extra,
    );
  }

  Request _prepareRequest(Request request, RequestOptions options) {
    final resolvedUrl = _resolveUrl(_mergeQuery(request.url, options.query));

    final mergedHeaders = Headers();
    _appendHeaders(mergedHeaders, _config.defaultHeaders);
    _appendHeaders(mergedHeaders, request.headers);
    _appendHeaders(mergedHeaders, options.headers);

    if (!isWebPlatform &&
        _config.userAgent.isNotEmpty &&
        !mergedHeaders.has('user-agent')) {
      mergedHeaders.set('user-agent', _config.userAgent);
    }

    return request.copyWith(url: resolvedUrl, headers: mergedHeaders);
  }

  Future<Response> _sendWithRetry(
    Request request,
    RequestOptions options,
  ) async {
    final retryPolicy = options.retryPolicy ?? const RetryPolicy();

    Object? lastError;
    Response? lastResponse;

    for (var attempt = 0; ; attempt++) {
      final attemptRequest = request.clone();

      try {
        final response = await _sendOnce(attemptRequest, options);

        if (_shouldRetryResponse(response, attemptRequest, options)) {
          lastResponse = response;
          if (attempt >= retryPolicy.maxRetries) {
            throw OxyRetryExhaustedException(
              attempts: attempt + 1,
              lastResponse: response,
            );
          }

          await _waitRetryDelay(attempt, options);
          continue;
        }

        return response;
      } catch (error, trace) {
        final normalized = _normalizeError(error, trace, options);
        lastError = normalized;

        if (_shouldRetryError(normalized, attemptRequest, options)) {
          if (attempt >= retryPolicy.maxRetries) {
            throw OxyRetryExhaustedException(
              attempts: attempt + 1,
              lastError: normalized,
            );
          }

          await _waitRetryDelay(attempt, options);
          continue;
        }

        if (lastResponse != null) {
          throw OxyRetryExhaustedException(
            attempts: attempt + 1,
            lastError: lastError,
            lastResponse: lastResponse,
            trace: trace,
          );
        }

        throw normalized;
      }
    }
  }

  Future<Response> _sendOnce(Request request, RequestOptions options) {
    final next = _buildPipeline(options.middleware);

    Future<Response> requestFuture = next(request, options);

    final timeout = options.requestTimeout;
    if (timeout != null) {
      requestFuture = requestFuture.timeout(
        timeout,
        onTimeout: () {
          final timeoutError = OxyTimeoutException(
            phase: TimeoutPhase.request,
            duration: timeout,
          );
          options.signal?.abort(timeoutError);
          throw timeoutError;
        },
      );
    }

    return requestFuture;
  }

  Next _buildPipeline(List<OxyMiddleware> middleware) {
    Next runner = (request, options) async {
      try {
        return await transport.fetchTransport(request, options);
      } catch (error, trace) {
        throw _normalizeError(error, trace, options);
      }
    };

    for (var i = middleware.length - 1; i >= 0; i--) {
      final current = middleware[i];
      final next = runner;

      runner = (request, options) async {
        try {
          return await current.intercept(request, options, next);
        } catch (error, trace) {
          if (error is OxyException) {
            rethrow;
          }

          throw OxyMiddlewareException(
            middleware: current.runtimeType.toString(),
            message: 'Middleware execution failed',
            cause: error,
            trace: trace,
          );
        }
      };
    }

    return runner;
  }

  bool _shouldRetryResponse(
    Response response,
    Request request,
    RequestOptions options,
  ) {
    final policy = options.retryPolicy ?? const RetryPolicy();
    if (!_allowMethodRetry(request, policy)) {
      return false;
    }

    return policy.retryableStatusCodes.contains(response.status);
  }

  bool _shouldRetryError(
    Object error,
    Request request,
    RequestOptions options,
  ) {
    final policy = options.retryPolicy ?? const RetryPolicy();
    if (!_allowMethodRetry(request, policy)) {
      return false;
    }

    if (error is OxyCancelledException || error is OxyDecodeException) {
      return false;
    }

    return error is OxyNetworkException || error is OxyTimeoutException;
  }

  bool _allowMethodRetry(Request request, RetryPolicy policy) {
    if (!policy.idempotentMethodsOnly) {
      return true;
    }

    const idempotentMethods = <String>{
      'GET',
      'HEAD',
      'OPTIONS',
      'PUT',
      'DELETE',
    };
    return idempotentMethods.contains(request.method);
  }

  Future<void> _waitRetryDelay(int attempt, RequestOptions options) {
    final policy = options.retryPolicy ?? const RetryPolicy();

    final exponentialMs = policy.baseDelay.inMilliseconds * (1 << attempt);
    final cappedMs = min(exponentialMs, policy.maxDelay.inMilliseconds);
    final jitterSpan = (cappedMs * 0.2).round();
    final jitter = jitterSpan == 0
        ? 0
        : _random.nextInt(jitterSpan * 2 + 1) - jitterSpan;

    final delay = Duration(milliseconds: max(0, cappedMs + jitter));

    final signal = options.signal;
    if (signal == null) {
      return Future<void>.delayed(delay);
    }

    if (signal.aborted) {
      throw OxyCancelledException(reason: signal.reason);
    }

    final completer = Completer<void>();
    final timer = Timer(delay, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    signal.onAbort(() {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(OxyCancelledException(reason: signal.reason));
      }
    });

    return completer.future;
  }

  Object _normalizeError(
    Object error,
    StackTrace trace,
    RequestOptions options,
  ) {
    if (options.signal?.aborted == true) {
      return OxyCancelledException(
        reason: options.signal?.reason,
        trace: trace,
      );
    }

    if (error is OxyException) {
      return error;
    }

    if (error is TimeoutException) {
      return OxyTimeoutException(
        phase: TimeoutPhase.request,
        duration: options.requestTimeout ?? Duration.zero,
        cause: error,
        trace: trace,
      );
    }

    if (error is Response) {
      return OxyHttpException(error, cause: error, trace: trace);
    }

    return OxyNetworkException(error.toString(), cause: error, trace: trace);
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

  Uri _resolveUrl(Uri url) {
    if (url.hasScheme) {
      return url;
    }

    if (_config.baseUrl != null) {
      return _config.baseUrl!.resolveUri(url);
    }

    throw ArgumentError.value(
      url.toString(),
      'request.url',
      'Relative URLs require `OxyConfig(baseUrl: ...)`.',
    );
  }

  static void _appendHeaders(Headers target, Headers? source) {
    if (source == null) {
      return;
    }

    for (final name in source.names()) {
      target.delete(name);
      for (final value in source.getAll(name)) {
        target.append(name, value);
      }
    }
  }

  static Uri _mergeQuery(Uri url, QueryMap? query) {
    if (query == null || query.isEmpty) {
      return url;
    }

    final merged = <String, List<String>>{};

    for (final entry in url.queryParametersAll.entries) {
      merged[entry.key] = List<String>.from(entry.value);
    }

    for (final entry in query.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }

      if (value is Iterable) {
        merged[entry.key] = value.map((item) => item.toString()).toList();
      } else {
        merged[entry.key] = <String>[value.toString()];
      }
    }

    final queryParts = <String>[];
    for (final entry in merged.entries) {
      for (final value in entry.value) {
        queryParts.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(value)}',
        );
      }
    }

    return url.replace(query: queryParts.join('&'));
  }
}

final Oxy oxy = Oxy();

Future<Response> fetch(
  String url, {
  String method = 'GET',
  QueryMap? query,
  Headers? headers,
  Object? body,
  Object? json,
  RequestOptions? options,
  ProgressCallback? onSendProgress,
  ProgressCallback? onReceiveProgress,
}) {
  return oxy.request(
    method,
    url,
    query: query,
    headers: headers,
    body: body,
    json: json,
    options: options,
    onSendProgress: onSendProgress,
    onReceiveProgress: onReceiveProgress,
  );
}

Future<OxyResult<Response>> safeFetch(
  String url, {
  String method = 'GET',
  QueryMap? query,
  Headers? headers,
  Object? body,
  Object? json,
  RequestOptions? options,
  ProgressCallback? onSendProgress,
  ProgressCallback? onReceiveProgress,
}) {
  return oxy.safeRequest(
    method,
    url,
    query: query,
    headers: headers,
    body: body,
    json: json,
    options: options,
    onSendProgress: onSendProgress,
    onReceiveProgress: onReceiveProgress,
  );
}

Future<T> fetchDecoded<T>(
  String url, {
  String method = 'GET',
  QueryMap? query,
  Headers? headers,
  Object? body,
  Object? json,
  RequestOptions? options,
  Decoder<T>? decoder,
}) {
  return oxy.requestDecoded<T>(
    method,
    url,
    query: query,
    headers: headers,
    body: body,
    json: json,
    options: options,
    decoder: decoder,
  );
}

Future<OxyResult<T>> safeFetchDecoded<T>(
  String url, {
  String method = 'GET',
  QueryMap? query,
  Headers? headers,
  Object? body,
  Object? json,
  RequestOptions? options,
  Decoder<T>? decoder,
}) {
  return oxy.safeRequestDecoded<T>(
    method,
    url,
    query: query,
    headers: headers,
    body: body,
    json: json,
    options: options,
    decoder: decoder,
  );
}
