import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'core/abort.dart';
import 'core/attributes.dart';
import 'core/body.dart';
import 'core/errors.dart';
import 'core/headers.dart';
import 'core/request.dart';
import 'core/response.dart';
import 'core/result.dart';
import 'options.dart';
import 'pipeline/context.dart';
import 'pipeline/events.dart';
import 'pipeline/middleware.dart';
import 'policies.dart';
import 'transport/default_transport.dart';
import 'transport/transport.dart';

final class Client {
  Client([ClientOptions options = const ClientOptions()])
    : options = options,
      _ownsTransport = options.transport == null,
      _transport =
          options.transport ??
          createDefaultTransport(keepAlive: options.keepAlive);

  final ClientOptions options;
  final Transport _transport;
  final bool _ownsTransport;
  final Random _random = Random();
  bool _closed = false;

  Transport get transport => _transport;

  Client withOptions(ClientOptions next) => Client(next);

  Client withMiddleware(List<Middleware> middleware, {bool replace = false}) {
    return Client(
      options.copyWith(
        middleware: replace
            ? middleware
            : <Middleware>[...options.middleware, ...middleware],
      ),
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsTransport) {
      await _transport.close();
    }
  }

  Future<Response> send(Request request, {RequestOptions? options}) async {
    if (_closed) {
      throw NetworkError('Client is closed.', request: request);
    }

    final resolved = _resolve(request, options);
    final prepared = resolved.request;
    var context = resolved.context;
    final totalTimeout = context.timeoutPolicy.total;
    final timeoutSignal = _needsInternalSignal(context.timeoutPolicy)
        ? _linkedSignal(context.signal)
        : null;
    if (timeoutSignal != null) {
      context = context.copyWith(signal: timeoutSignal);
    }
    final hooks = this.options.hooks.merge(context.requestOptions.hooks);

    emitEvent(
      context.onEvent,
      RequestEventType.start,
      request: prepared,
      attempt: 0,
    );

    Future<Response> run() async {
      try {
        await hooks.onRequest?.call(prepared, context);
        final response = await _runApplicationPipeline(prepared, context);
        final nextResponse =
            await hooks.onResponse?.call(prepared, response, context) ??
            response;
        emitEvent(
          context.onEvent,
          RequestEventType.complete,
          request: prepared,
          attempt: context.attempt,
          response: nextResponse,
        );
        return nextResponse;
      } catch (error) {
        await hooks.onError?.call(prepared, error, context);
        rethrow;
      } finally {
        await hooks.onFinally?.call(prepared, context);
      }
    }

    if (totalTimeout == null) {
      return run();
    }

    return run().timeout(
      totalTimeout,
      onTimeout: () {
        final timeoutError = TimeoutError(
          phase: TimeoutPhase.total,
          duration: totalTimeout,
          request: prepared,
        );
        timeoutSignal?.abort(timeoutError);
        throw timeoutError;
      },
    );
  }

  AbortSignal _linkedSignal(AbortSignal? parent) {
    final signal = AbortSignal();
    if (parent == null) {
      return signal;
    }

    if (parent.aborted) {
      signal.abort(parent.reason);
    } else {
      parent.onAbort(() {
        signal.abort(parent.reason);
      });
    }
    return signal;
  }

  bool _needsInternalSignal(TimeoutPolicy policy) {
    return policy.total != null ||
        policy.send != null ||
        policy.firstByte != null ||
        policy.read != null;
  }

  Future<Result<Response>> sendResult(
    Request request, {
    RequestOptions? options,
  }) {
    return Result.capture(() => send(request, options: options));
  }

  Future<Response> request(
    String method,
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    final requestHeaders = Headers(headers);
    final requestBody = _resolveBody(body: body, json: json);
    if (requestBody?.contentType != null &&
        !requestHeaders.has('content-type')) {
      requestHeaders.set('content-type', requestBody!.contentType!);
    }

    final requestOptions = (options ?? const RequestOptions()).copyWith(
      query: query,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return send(
      Request(
        url,
        method: method.toUpperCase(),
        headers: requestHeaders,
        body: requestBody,
        options: requestOptions,
      ),
    );
  }

  Future<Result<Response>> requestResult(
    String method,
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return Result.capture(
      () => request(
        method,
        url,
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

  Future<Response> get(
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    RequestOptions? options,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'GET',
      url,
      query: query,
      headers: headers,
      options: options,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<Response> post(
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'POST',
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

  Future<Response> put(
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'PUT',
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

  Future<Response> patch(
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'PATCH',
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

  Future<Response> delete(
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request(
      'DELETE',
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

  Future<Response> head(
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    RequestOptions? options,
  }) {
    return request(
      'HEAD',
      url,
      query: query,
      headers: headers,
      options: options,
    );
  }

  Future<Response> optionsRequest(
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
  }) {
    return request(
      'OPTIONS',
      url,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
  }

  Future<T> decode<T>(
    String method,
    Object url, {
    QueryMap? query,
    HeadersInit? headers,
    Object? body,
    Object? json,
    RequestOptions? options,
    Decoder<T>? decoder,
  }) async {
    final response = await request(
      method,
      url,
      query: query,
      headers: headers,
      body: body,
      json: json,
      options: options,
    );
    return response.decode<T>(decoder: decoder);
  }

  _ResolvedRequest _resolve(Request request, RequestOptions? sendOptions) {
    final incoming = _mergeRequestOptions(request.options, sendOptions);
    final timeoutPolicy = incoming.timeoutPolicy ?? options.timeoutPolicy;
    final retryPolicy = incoming.retryPolicy ?? options.retryPolicy;
    final redirectPolicy = incoming.redirectPolicy ?? options.redirectPolicy;
    final statusPolicy = incoming.statusPolicy ?? options.statusPolicy;

    final attributes = _mergeAttributes(
      options.attributes,
      request.attributes,
      incoming.attributes,
    );

    final context = Context(
      clientOptions: options,
      requestOptions: incoming,
      timeoutPolicy: timeoutPolicy,
      retryPolicy: retryPolicy,
      redirectPolicy: redirectPolicy,
      statusPolicy: statusPolicy,
      capability: _transport.capability,
      attributes: attributes,
      createdAt: DateTime.now().toUtc(),
      attempt: 0,
      signal: incoming.signal,
      onEvent: options.onEvent,
    );

    final resolvedUrl = _resolveUrl(_mergeQuery(request.uri, incoming.query));
    final headers = Headers(options.defaultHeaders);
    for (final name in request.headers.keys()) {
      headers.delete(name);
      for (final value in request.headers.getAll(name)) {
        headers.append(name, value);
      }
    }
    if (incoming.headers != null) {
      final override = Headers(incoming.headers);
      for (final name in override.keys()) {
        headers.delete(name);
        for (final value in override.getAll(name)) {
          headers.append(name, value);
        }
      }
    }
    if (options.userAgent.isNotEmpty && !headers.has('user-agent')) {
      headers.set('user-agent', options.userAgent);
    }

    final body = request.body;
    if (body?.contentType != null && !headers.has('content-type')) {
      headers.set('content-type', body!.contentType!);
    }
    if (context.capability.name != 'web' &&
        body?.contentLength != null &&
        !headers.has('content-length')) {
      headers.set('content-length', body!.contentLength!);
    }

    final prepared = request.copyWith(
      method: request.method.toUpperCase(),
      uri: resolvedUrl,
      headers: headers,
      options: incoming,
      attributes: attributes,
    );

    emitEvent(
      context.onEvent,
      RequestEventType.prepared,
      request: prepared,
      attempt: 0,
    );

    return _ResolvedRequest(prepared, context);
  }

  Future<Response> _runApplicationPipeline(Request request, Context context) {
    final middleware = <Middleware>[
      ...options.middleware,
      ...context.requestOptions.middleware,
    ];

    return _buildPipeline(
      middleware,
      (nextRequest, nextContext) => _runOperation(nextRequest, nextContext),
    )(request, context);
  }

  Future<Response> _runOperation(Request request, Context context) async {
    final retryPolicy = context.retryPolicy;
    Object? lastError;
    Response? lastResponse;

    for (var attempt = 0; ; attempt++) {
      final attemptContext = context.copyWith(attempt: attempt);

      if (attempt > 0 && request.body != null && !request.body!.replayable) {
        attemptContext.emit(
          RequestEventType.retrySkipped,
          request,
          detail: 'request body is not replayable',
        );
        throw RetryError(
          attempts: attempt,
          lastError: lastError,
          lastResponse: lastResponse,
          request: request,
        );
      }

      try {
        _throwIfAborted(attemptContext.signal, request);
        emitEvent(
          attemptContext.onEvent,
          RequestEventType.attemptStart,
          request: request,
          attempt: attempt,
        );

        var response = await _runNetworkPipeline(request, attemptContext);
        response = _withReadTimeout(response, request, attemptContext);

        emitEvent(
          attemptContext.onEvent,
          RequestEventType.attemptEnd,
          request: request,
          attempt: attempt,
          response: response,
        );

        if (_isRedirectBlocked(response, attemptContext)) {
          throw StatusError(
            response,
            request: request,
            message: 'Redirect blocked by RedirectPolicy.error.',
          );
        }

        if (_shouldRetryResponse(request, response, attemptContext)) {
          lastResponse = response;
          if (attempt >= retryPolicy.maxRetries) {
            throw RetryError(
              attempts: attempt + 1,
              lastResponse: response,
              request: request,
            );
          }

          await response.drain(maxBytes: null);
          final delay = retryPolicy.delayFor(
            attempt,
            response: response,
            random: _random,
          );
          await _beforeRetry(request, attemptContext, null, response, delay);
          await _waitRetryDelay(delay, attemptContext);
          continue;
        }

        if (!attemptContext.statusPolicy.accepts(response)) {
          final preview = await _previewStatusBody(response, attemptContext);
          emitEvent(
            attemptContext.onEvent,
            RequestEventType.statusFailed,
            request: request,
            attempt: attempt,
            response: response,
          );
          throw StatusError(response, request: request, bodyPreview: preview);
        }

        return response;
      } catch (error, trace) {
        final normalized = _normalizeError(error, trace, request, context);
        lastError = normalized;

        if (_shouldRetryError(request, normalized, attemptContext)) {
          if (attempt >= retryPolicy.maxRetries) {
            throw RetryError(
              attempts: attempt + 1,
              lastError: normalized,
              lastResponse: lastResponse,
              request: request,
              trace: trace,
            );
          }

          final delay = retryPolicy.delayFor(attempt, random: _random);
          await _beforeRetry(request, attemptContext, normalized, null, delay);
          await _waitRetryDelay(delay, attemptContext);
          continue;
        }

        throw normalized;
      }
    }
  }

  Future<Response> _runNetworkPipeline(Request request, Context context) {
    final middleware = <Middleware>[
      ...options.networkMiddleware,
      ...context.requestOptions.networkMiddleware,
    ];

    final operation = _buildPipeline(
      middleware,
      (nextRequest, nextContext) => _transport.send(nextRequest, nextContext),
    )(request, context);
    final timeout = context.timeoutPolicy.firstByte;
    if (timeout == null) {
      return operation;
    }
    return operation.timeout(
      timeout,
      onTimeout: () {
        final timeoutError = TimeoutError(
          phase: TimeoutPhase.firstByte,
          duration: timeout,
          request: request,
        );
        context.signal?.abort(timeoutError);
        throw timeoutError;
      },
    );
  }

  void _throwIfAborted(AbortSignal? signal, Request request) {
    if (signal?.aborted == true) {
      throw CancelError(reason: signal?.reason, request: request);
    }
  }

  Response _withReadTimeout(
    Response response,
    Request request,
    Context context,
  ) {
    final timeout = context.timeoutPolicy.read;
    final body = response.body;
    if (timeout == null || body == null) {
      return response;
    }

    return response.copyWith(
      body: ResponseBody.stream(
        _readTimeoutStream(body.open(), timeout, request, context.signal),
        contentLength: body.contentLength,
      ),
    );
  }

  Stream<List<int>> _readTimeoutStream(
    Stream<List<int>> source,
    Duration timeout,
    Request request,
    AbortSignal? signal,
  ) async* {
    final iterator = StreamIterator<List<int>>(source);
    try {
      while (true) {
        final hasNext = await iterator.moveNext().timeout(
          timeout,
          onTimeout: () {
            final timeoutError = TimeoutError(
              phase: TimeoutPhase.read,
              duration: timeout,
              request: request,
              sent: true,
            );
            signal?.abort(timeoutError);
            throw timeoutError;
          },
        );
        if (!hasNext) {
          break;
        }
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  Next _buildPipeline(List<Middleware> middleware, Next terminal) {
    Next runner = terminal;

    for (var i = middleware.length - 1; i >= 0; i--) {
      final current = middleware[i];
      final next = runner;
      runner = (request, context) async {
        try {
          return await current.intercept(request, context, next);
        } catch (error, trace) {
          if (error is RequestError) {
            rethrow;
          }
          throw MiddlewareError(
            middleware: current.runtimeType.toString(),
            message: 'Middleware execution failed.',
            request: request,
            cause: error,
            trace: trace,
          );
        }
      };
    }

    return runner;
  }

  bool _shouldRetryResponse(
    Request request,
    Response response,
    Context context,
  ) {
    final policy = context.retryPolicy;
    if (policy.maxRetries <= 0 ||
        !policy.allowsMethod(request) ||
        request.body?.replayable == false) {
      return false;
    }
    return policy.shouldRetryResponse(response);
  }

  bool _shouldRetryError(Request request, Object error, Context context) {
    final policy = context.retryPolicy;
    if (policy.maxRetries <= 0 ||
        !policy.allowsMethod(request) ||
        request.body?.replayable == false) {
      return false;
    }
    if (error is CancelError || error is DecodeError) {
      return false;
    }
    if (error is TimeoutError) {
      return error.retryable;
    }
    if (error is NetworkError) {
      return error.retryable;
    }
    return false;
  }

  bool _isRedirectBlocked(Response response, Context context) {
    return context.redirectPolicy.mode == RedirectMode.error &&
        response.status >= 300 &&
        response.status <= 399;
  }

  Future<void> _beforeRetry(
    Request request,
    Context context,
    Object? error,
    Response? response,
    Duration delay,
  ) async {
    emitEvent(
      context.onEvent,
      RequestEventType.retryScheduled,
      request: request,
      attempt: context.attempt,
      response: response,
      error: error,
      detail: delay.toString(),
    );
    await context.clientOptions.hooks
        .merge(context.requestOptions.hooks)
        .onRetry
        ?.call(request, error, response, delay, context);
  }

  Future<void> _waitRetryDelay(Duration delay, Context context) {
    final signal = context.signal;
    if (signal == null) {
      return Future<void>.delayed(delay);
    }
    if (signal.aborted) {
      throw CancelError(reason: signal.reason);
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
        completer.completeError(CancelError(reason: signal.reason));
      }
    });
    return completer.future;
  }

  Object _normalizeError(
    Object error,
    StackTrace trace,
    Request request,
    Context context,
  ) {
    if (context.signal?.aborted == true) {
      if (context.signal?.reason case final TimeoutError timeoutError) {
        return timeoutError;
      }
      if (error is TimeoutError) {
        return error;
      }
      return CancelError(
        reason: context.signal?.reason,
        request: request,
        trace: trace,
      );
    }
    if (error is RequestError) {
      return error;
    }
    if (error is TimeoutException) {
      return TimeoutError(
        phase: TimeoutPhase.total,
        duration: context.timeoutPolicy.total ?? Duration.zero,
        request: request,
        cause: error,
        trace: trace,
      );
    }
    return NetworkError(
      error.toString(),
      request: request,
      cause: error,
      trace: trace,
    );
  }

  Future<String?> _previewStatusBody(Response response, Context context) async {
    final limit = context.clientOptions.errorBodyPreviewLimit;
    final body = response.body;
    if (limit <= 0 || body == null) {
      return null;
    }

    try {
      final iterator = StreamIterator<Uint8List>(body.open());
      final chunks = <Uint8List>[];
      final builder = BytesBuilder(copy: false);

      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        chunks.add(chunk);
        builder.add(chunk);
        if (builder.length > limit) {
          response.body = ResponseBody.stream(
            _restorePreviewStream(chunks, iterator),
            contentLength: body.contentLength,
          );
          return null;
        }
      }

      final data = builder.takeBytes();
      response.body = ResponseBody.fromBytes(data);
      return utf8.decode(data);
    } catch (_) {
      return null;
    }
  }

  Stream<List<int>> _restorePreviewStream(
    List<Uint8List> chunks,
    StreamIterator<Uint8List> iterator,
  ) async* {
    try {
      for (final chunk in chunks) {
        yield chunk;
      }
      while (await iterator.moveNext()) {
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  RequestOptions _mergeRequestOptions(
    RequestOptions requestOptions,
    RequestOptions? sendOptions,
  ) {
    if (sendOptions == null) {
      return requestOptions;
    }

    return requestOptions.copyWith(
      headers: sendOptions.headers,
      query: sendOptions.query,
      timeoutPolicy: sendOptions.timeoutPolicy,
      retryPolicy: sendOptions.retryPolicy,
      redirectPolicy: sendOptions.redirectPolicy,
      statusPolicy: sendOptions.statusPolicy,
      middleware: <Middleware>[
        ...requestOptions.middleware,
        ...sendOptions.middleware,
      ],
      networkMiddleware: <Middleware>[
        ...requestOptions.networkMiddleware,
        ...sendOptions.networkMiddleware,
      ],
      hooks:
          requestOptions.hooks?.merge(sendOptions.hooks) ?? sendOptions.hooks,
      signal: sendOptions.signal,
      onSendProgress: sendOptions.onSendProgress,
      onReceiveProgress: sendOptions.onReceiveProgress,
      attributes: _mergeAttributes(
        requestOptions.attributes,
        sendOptions.attributes,
      ),
    );
  }

  Attributes _mergeAttributes(
    Attributes first,
    Attributes second, [
    Attributes third = const Attributes(),
  ]) {
    var merged = Attributes(first.toMap());
    for (final entry in second.toMap().entries) {
      merged = merged.set(entry.key, entry.value);
    }
    for (final entry in third.toMap().entries) {
      merged = merged.set(entry.key, entry.value);
    }
    return merged;
  }

  Uri _resolveUrl(Uri url) {
    if (url.hasScheme) {
      return url;
    }
    final baseUrl = options.baseUrl;
    if (baseUrl == null) {
      throw ArgumentError.value(
        url.toString(),
        'url',
        'Relative URLs require ClientOptions(baseUrl: ...).',
      );
    }
    return baseUrl.resolveUri(url);
  }

  Uri _mergeQuery(Uri uri, QueryMap? query) {
    if (query == null || query.isEmpty) {
      return uri;
    }

    final merged = <String, List<String>>{
      for (final entry in uri.queryParametersAll.entries)
        entry.key: List<String>.from(entry.value),
    };

    for (final entry in query.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is Iterable && value is! String) {
        merged[entry.key] = value.map((item) => item.toString()).toList();
      } else {
        merged[entry.key] = <String>[value.toString()];
      }
    }

    final parts = <String>[];
    for (final entry in merged.entries) {
      for (final value in entry.value) {
        parts.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(value)}',
        );
      }
    }
    return uri.replace(query: parts.join('&'));
  }

  Body? _resolveBody({required Object? body, required Object? json}) {
    if (body != null && json != null) {
      throw ArgumentError('Use either body or json, not both.');
    }
    if (json != null) {
      return Body.fromJson(json);
    }
    return Body.from(body);
  }
}

final class _ResolvedRequest {
  const _ResolvedRequest(this.request, this.context);

  final Request request;
  final Context context;
}

final Client client = Client();

Future<Response> fetch(
  Object url, {
  String method = 'GET',
  QueryMap? query,
  HeadersInit? headers,
  Object? body,
  Object? json,
  RequestOptions? options,
  ProgressCallback? onSendProgress,
  ProgressCallback? onReceiveProgress,
}) {
  return client.request(
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

Future<Result<Response>> fetchResult(
  Object url, {
  String method = 'GET',
  QueryMap? query,
  HeadersInit? headers,
  Object? body,
  Object? json,
  RequestOptions? options,
  ProgressCallback? onSendProgress,
  ProgressCallback? onReceiveProgress,
}) {
  return client.requestResult(
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
