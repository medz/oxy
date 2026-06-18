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
import 'pipeline/internal_attributes.dart';
import 'pipeline/middleware.dart';
import 'policies.dart';
import 'transport/default_transport.dart';
import 'transport/transport.dart';

const Object _jsonOmitted = Object();

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
    var finalAttempt = context.attempt;
    final onEvent = context.onEvent;
    if (onEvent != null) {
      // Attempts are owned by _runOperation; keep the request-level complete
      // event aligned with the attempt that actually returned.
      context = context.copyWith(
        onEvent: (event) {
          if (event.type == RequestEventType.attemptEnd) {
            finalAttempt = event.attempt;
          }
          onEvent(event);
        },
      );
    }
    final hooks = this.options.hooks.merge(context.requestOptions.hooks);
    var lifecycleClosed = false;

    Future<void> closeLifecycle({Object? error}) async {
      if (lifecycleClosed) {
        return;
      }
      lifecycleClosed = true;
      if (error == null) {
        await hooks.onFinally?.call(prepared, context);
        return;
      }
      try {
        await hooks.onError?.call(prepared, error, context);
      } finally {
        await hooks.onFinally?.call(prepared, context);
      }
    }

    void throwIfLifecycleClosed() {
      if (!lifecycleClosed) {
        return;
      }
      if (context.signal?.reason case final TimeoutError timeoutError) {
        throw timeoutError;
      }
      throw CancelError(reason: context.signal?.reason, request: prepared);
    }

    emitEvent(
      context.onEvent,
      RequestEventType.start,
      request: prepared,
      attempt: 0,
    );
    emitEvent(
      context.onEvent,
      RequestEventType.prepared,
      request: prepared,
      attempt: 0,
    );

    Future<Response> run() async {
      try {
        await hooks.onRequest?.call(prepared, context);
        throwIfLifecycleClosed();
        final response = await _runApplicationPipeline(prepared, context);
        throwIfLifecycleClosed();
        final nextResponse =
            await hooks.onResponse?.call(prepared, response, context) ??
            response;
        throwIfLifecycleClosed();
        emitEvent(
          context.onEvent,
          RequestEventType.complete,
          request: prepared,
          attempt: finalAttempt,
          response: nextResponse,
        );
        return nextResponse;
      } catch (error) {
        await closeLifecycle(error: error);
        rethrow;
      } finally {
        await closeLifecycle();
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
        return closeLifecycle(error: timeoutError).then<Response>((_) {
          throw timeoutError;
        });
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
    Object? json = _jsonOmitted,
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
    Object? json = _jsonOmitted,
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
    Object? json = _jsonOmitted,
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
    Object? json = _jsonOmitted,
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
    Object? json = _jsonOmitted,
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
    Object? json = _jsonOmitted,
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
    Object? json = _jsonOmitted,
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
    Object? json = _jsonOmitted,
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
    if (context.capability.name != 'web' &&
        options.userAgent.isNotEmpty &&
        !headers.has('user-agent')) {
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

    return _ResolvedRequest(prepared, context);
  }

  Future<Response> _runApplicationPipeline(Request request, Context context) {
    final middleware = <Middleware>[
      ...options.middleware,
      ...context.requestOptions.middleware,
    ];

    final next = _buildPipeline(
      middleware,
      (nextRequest, nextContext) => _runOperation(nextRequest, nextContext),
    );
    if (_usesClientRedirects(context)) {
      return _runRedirects(request, context, next);
    }
    return next(request, context);
  }

  bool _usesClientRedirects(Context context) {
    return context.redirectPolicy.mode == RedirectMode.follow &&
        context.capability.name != 'web';
  }

  Future<Response> _runRedirects(
    Request request,
    Context context,
    Next next,
  ) async {
    var current = request;
    var redirected = false;
    for (var redirects = 0; ; redirects++) {
      final response = await next(current, _allowRedirectStatus(context));
      if (!_isRedirectStatus(response.status)) {
        return redirected ? response.copyWith(redirected: true) : response;
      }

      final location = response.headers.get('location');
      if (location == null || location.trim().isEmpty) {
        throw StatusError(
          response,
          request: current,
          message: 'Redirect response is missing a Location header.',
        );
      }
      if (redirects >= context.redirectPolicy.maxRedirects) {
        throw StatusError(
          response,
          request: current,
          message: 'Too many redirects.',
        );
      }
      if (!_redirectChangesToGet(response.status, current.method) &&
          current.body?.replayable == false) {
        await response.drain(maxBytes: null);
        throw StatusError(
          response,
          request: current,
          message: 'Redirect requires a replayable request body.',
        );
      }

      await response.drain(maxBytes: null);
      current = _redirectRequest(current, response, location);
      redirected = true;
    }
  }

  Context _allowRedirectStatus(Context context) {
    return context.copyWith(
      statusPolicy: StatusPolicy(
        accept: (response) {
          return _isRedirectStatus(response.status) ||
              context.statusPolicy.accepts(response);
        },
      ),
    );
  }

  Request _redirectRequest(
    Request request,
    Response response,
    String location,
  ) {
    final base = response.url.hasScheme ? response.url : request.uri;
    final nextUri = base.resolve(location);
    final sameOrigin = _sameOrigin(request.uri, nextUri);
    final nextHeaders = request.headers.copy();
    var nextAttributes = request.attributes;
    if (!sameOrigin) {
      nextHeaders.delete('authorization');
      nextHeaders.delete('cookie');
      nextHeaders.delete('proxy-authorization');
      nextAttributes = nextAttributes
          .remove(cookieHeaderManagedAttribute)
          .set(redirectCrossOriginAttribute, true);
    }

    var method = request.method;
    var clearBody = false;
    if (_redirectChangesToGet(response.status, method)) {
      method = 'GET';
      clearBody = true;
      nextHeaders.delete('content-length');
      nextHeaders.delete('content-type');
    }

    return request.copyWith(
      method: method,
      uri: nextUri,
      headers: nextHeaders,
      clearBody: clearBody,
      attributes: nextAttributes,
    );
  }

  bool _redirectChangesToGet(int status, String method) {
    final upper = method.toUpperCase();
    if (status == 303 && upper != 'GET' && upper != 'HEAD') {
      return true;
    }
    return (status == 301 || status == 302) && upper == 'POST';
  }

  bool _sameOrigin(Uri a, Uri b) {
    return a.scheme == b.scheme && a.host == b.host && _portOf(a) == _portOf(b);
  }

  int _portOf(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return switch (uri.scheme) {
      'http' => 80,
      'https' => 443,
      _ => 0,
    };
  }

  Future<Response> _runOperation(Request request, Context context) async {
    final retryPolicy = context.retryPolicy;
    Object? lastError;
    Response? lastResponse;

    for (var attempt = 0; ; attempt++) {
      final attemptSignal = _linkedSignal(context.signal);
      final attemptContext = context.copyWith(
        attempt: attempt,
        signal: attemptSignal,
      );
      final attemptRequest = _sanitizeRedirectHeaders(request);

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
        _throwIfAborted(attemptContext.signal, attemptRequest);
        emitEvent(
          attemptContext.onEvent,
          RequestEventType.attemptStart,
          request: attemptRequest,
          attempt: attempt,
        );

        var response = await _runNetworkPipeline(
          attemptRequest,
          attemptContext,
        );
        response = _withReadTimeout(response, attemptRequest, attemptContext);
        response = _withTotalTimeout(response, attemptRequest, attemptContext);

        emitEvent(
          attemptContext.onEvent,
          RequestEventType.attemptEnd,
          request: attemptRequest,
          attempt: attempt,
          response: response,
        );

        if (_isRedirectBlocked(response, attemptContext)) {
          throw StatusError(
            response,
            request: attemptRequest,
            message: 'Redirect blocked by RedirectPolicy.error.',
          );
        }

        if (_shouldRetryResponse(attemptRequest, response, attemptContext)) {
          lastResponse = response;
          if (attempt >= retryPolicy.maxRetries) {
            throw RetryError(
              attempts: attempt + 1,
              lastResponse: response,
              request: attemptRequest,
            );
          }

          await response.drain(maxBytes: null);
          final delay = retryPolicy.delayFor(
            attempt,
            response: response,
            random: _random,
          );
          final retryContext = attemptContext.copyWith(signal: context.signal);
          await _beforeRetry(
            attemptRequest,
            retryContext,
            null,
            response,
            delay,
          );
          await _waitRetryDelay(delay, retryContext);
          continue;
        }

        if (!attemptContext.statusPolicy.accepts(response)) {
          final preview = await _previewStatusBody(response, attemptContext);
          emitEvent(
            attemptContext.onEvent,
            RequestEventType.statusFailed,
            request: attemptRequest,
            attempt: attempt,
            response: response,
          );
          throw StatusError(
            response,
            request: attemptRequest,
            bodyPreview: preview,
          );
        }

        return response;
      } catch (error, trace) {
        final normalized = _normalizeError(
          error,
          trace,
          attemptRequest,
          attemptContext,
        );
        lastError = normalized;

        if (_shouldRetryError(attemptRequest, normalized, attemptContext)) {
          if (attempt >= retryPolicy.maxRetries) {
            throw RetryError(
              attempts: attempt + 1,
              lastError: normalized,
              lastResponse: lastResponse,
              request: attemptRequest,
              trace: trace,
            );
          }

          final delay = retryPolicy.delayFor(attempt, random: _random);
          final retryContext = attemptContext.copyWith(signal: context.signal);
          await _beforeRetry(
            attemptRequest,
            retryContext,
            normalized,
            null,
            delay,
          );
          await _waitRetryDelay(delay, retryContext);
          continue;
        }

        throw normalized;
      }
    }
  }

  Request _sanitizeRedirectHeaders(Request request) {
    if (request.attributes.get(redirectCrossOriginAttribute) != true) {
      return request;
    }

    final headers = request.headers.copy()
      ..delete('authorization')
      ..delete('proxy-authorization');
    if (request.attributes.get(cookieHeaderManagedAttribute) != true) {
      headers.delete('cookie');
    }
    return request.copyWith(headers: headers);
  }

  Future<Response> _runNetworkPipeline(Request request, Context context) {
    final middleware = <Middleware>[
      ...options.networkMiddleware,
      ...context.requestOptions.networkMiddleware,
    ];

    final operation = _buildPipeline(middleware, (nextRequest, nextContext) {
      return _transport.send(
        _sanitizeRedirectHeaders(nextRequest),
        nextContext,
      );
    })(request, context);
    return operation;
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
    if (timeout == null || body == null || body.replayable) {
      return response;
    }

    return response.copyWith(
      body: ResponseBody.stream(
        _readTimeoutStream(body.open(), timeout, request),
        contentLength: body.contentLength,
      ),
    );
  }

  Response _withTotalTimeout(
    Response response,
    Request request,
    Context context,
  ) {
    final timeout = context.timeoutPolicy.total;
    final body = response.body;
    if (timeout == null || body == null || body.replayable) {
      return response;
    }

    final deadline = context.createdAt.add(timeout);
    return response.copyWith(
      body: ResponseBody.stream(
        _totalTimeoutStream(
          body.open(),
          timeout,
          deadline,
          request,
          context.signal,
        ),
        contentLength: body.contentLength,
      ),
    );
  }

  Stream<List<int>> _readTimeoutStream(
    Stream<List<int>> source,
    Duration timeout,
    Request request,
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

  Stream<List<int>> _totalTimeoutStream(
    Stream<List<int>> source,
    Duration timeout,
    DateTime deadline,
    Request request,
    AbortSignal? signal,
  ) async* {
    final iterator = StreamIterator<List<int>>(source);
    try {
      while (true) {
        final remaining = deadline.difference(DateTime.now().toUtc());
        if (remaining <= Duration.zero) {
          throw _abortTotalTimeout(timeout, request, signal);
        }

        final hasNext = await iterator.moveNext().timeout(
          remaining,
          onTimeout: () {
            throw _abortTotalTimeout(timeout, request, signal);
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

  TimeoutError _abortTotalTimeout(
    Duration timeout,
    Request request,
    AbortSignal? signal,
  ) {
    final timeoutError = TimeoutError(
      phase: TimeoutPhase.total,
      duration: timeout,
      request: request,
      sent: true,
    );
    signal?.abort(timeoutError);
    return timeoutError;
  }

  Next _buildPipeline(List<Middleware> middleware, Next terminal) {
    Next runner = terminal;

    for (var i = middleware.length - 1; i >= 0; i--) {
      final current = middleware[i];
      final next = runner;
      runner = (request, context) async {
        final middlewareName = current.runtimeType.toString();
        Future<Response> guardedNext(Request request, Context context) async {
          try {
            return await next(request, context);
          } catch (error, trace) {
            if (error is RequestError) {
              Error.throwWithStackTrace(error, trace);
            }
            throw _DownstreamError(error, trace);
          }
        }

        void emitMiddlewareEnd({Response? response, Object? error}) {
          emitEvent(
            context.onEvent,
            RequestEventType.middlewareEnd,
            request: request,
            attempt: context.attempt,
            response: response,
            error: error,
            detail: middlewareName,
          );
        }

        emitEvent(
          context.onEvent,
          RequestEventType.middlewareStart,
          request: request,
          attempt: context.attempt,
          detail: middlewareName,
        );
        late Response response;
        try {
          response = await current.intercept(request, context, guardedNext);
        } catch (error, trace) {
          if (error is _DownstreamError) {
            emitMiddlewareEnd(error: error.error);
            Error.throwWithStackTrace(error.error, error.trace);
          }
          if (error is RequestError) {
            emitMiddlewareEnd(error: error);
            rethrow;
          }
          final middlewareError = MiddlewareError(
            middleware: middlewareName,
            message: 'Middleware execution failed.',
            request: request,
            cause: error,
            trace: trace,
          );
          emitMiddlewareEnd(error: middlewareError);
          throw middlewareError;
        }
        emitMiddlewareEnd(response: response);
        return response;
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
        _isRedirectStatus(response.status);
  }

  bool _isRedirectStatus(int status) {
    return switch (status) {
      301 || 302 || 303 || 307 || 308 => true,
      _ => false,
    };
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
    if (body != null && !identical(json, _jsonOmitted)) {
      throw ArgumentError('Use either body or json, not both.');
    }
    if (!identical(json, _jsonOmitted)) {
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

final class _DownstreamError {
  const _DownstreamError(this.error, this.trace);

  final Object error;
  final StackTrace trace;
}

final Client client = Client();

Future<Response> fetch(
  Object url, {
  String method = 'GET',
  QueryMap? query,
  HeadersInit? headers,
  Object? body,
  Object? json = _jsonOmitted,
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
  Object? json = _jsonOmitted,
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
