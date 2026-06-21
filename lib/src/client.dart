import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'core/abort.dart';
import 'core/body.dart';
import 'core/errors.dart';
import 'core/headers.dart';
import 'core/request.dart';
import 'core/response.dart';
import 'core/result.dart';
import 'client/request_resolution.dart';
import 'options.dart';
import 'pipeline/context.dart';
import 'pipeline/events.dart';
import 'pipeline/internal_attributes.dart';
import 'pipeline/middleware.dart';
import 'policies.dart';
import 'transport/default_transport.dart';
import 'transport/transport.dart';

const Object _jsonOmitted = Object();

final class _StatusBodyPreview {
  const _StatusBodyPreview({required this.response, this.bodyPreview});

  final Response response;
  final String? bodyPreview;
}

/// A reusable HTTP client with shared options, middleware, and transport state.
///
/// Create a [Client] when requests should share a base URL, default headers,
/// retry and timeout policies, middleware, or native keep-alive connections.
/// For one-off requests, use [fetch].
///
/// ```dart
/// final client = Client(
///   ClientOptions(baseUrl: Uri.parse('https://api.example.com')),
/// );
///
/// try {
///   final response = await client.get('/users/1');
///   print(await response.json<Map<String, Object?>>());
/// } finally {
///   await client.close();
/// }
/// ```
///
/// A client owns its default transport unless [ClientOptions.transport] is set.
/// Call [close] when a long-lived client is no longer needed.
final class Client {
  Client([ClientOptions options = const ClientOptions()])
    : options = options,
      _ownsTransport = options.transport == null,
      _transport =
          options.transport ??
          createDefaultTransport(keepAlive: options.keepAlive);

  /// The defaults applied to requests sent by this client.
  final ClientOptions options;
  final Transport _transport;
  final bool _ownsTransport;
  final Random _random = Random();
  bool _closed = false;

  /// The transport used after request resolution, policies, and middleware.
  Transport get transport => _transport;

  /// Creates a new client with [next] as its options.
  Client withOptions(ClientOptions next) => Client(next);

  /// Creates a new client with additional application [middleware].
  ///
  /// When [replace] is `true`, [middleware] replaces the existing application
  /// middleware list instead of being appended to it.
  Client withMiddleware(List<Middleware> middleware, {bool replace = false}) {
    return Client(
      options.copyWith(
        middleware: replace
            ? middleware
            : <Middleware>[...options.middleware, ...middleware],
      ),
    );
  }

  /// Closes the client-owned transport.
  ///
  /// This method is idempotent. It only closes the transport that Oxy created
  /// for this client; a custom [ClientOptions.transport] remains owned by the
  /// caller.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsTransport) {
      await _transport.close();
    }
  }

  /// Sends a prepared [request].
  ///
  /// The request is resolved against [ClientOptions.baseUrl], merged with
  /// default headers and [options], then passed through middleware, retry,
  /// redirect, timeout, and status policies.
  ///
  /// Throws a [RequestError] subtype for network, timeout, status, retry,
  /// decode, body, and middleware failures.
  Future<Response> send(Request request, {RequestOptions? options}) async {
    if (_closed) {
      throw NetworkError('Client is closed.', request: request);
    }

    final resolved = resolveClientRequest(
      request,
      options,
      clientOptions: this.options,
      capability: _transport.capability,
    );
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
        final pipelineResult = await _runApplicationPipeline(prepared, context);
        var response = pipelineResult.response;
        throwIfLifecycleClosed();
        if (!pipelineResult.reachedTerminal) {
          response = await _completeShortCircuitedResponse(
            prepared,
            response,
            context,
          );
        }
        throwIfLifecycleClosed();
        final policyResponse = await _applyResponsePolicies(
          prepared,
          response,
          context,
        );
        throwIfLifecycleClosed();
        final nextResponse =
            await hooks.onResponse?.call(prepared, policyResponse, context) ??
            policyResponse;
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

  /// Sends [request] and captures success or failure in a [Result].
  ///
  /// This is the no-throw form of [send].
  Future<Result<Response>> sendResult(
    Request request, {
    RequestOptions? options,
  }) {
    return Result.capture(() => send(request, options: options));
  }

  /// Sends a request built from a method and URL.
  ///
  /// [url] can be a [String] or [Uri]. Relative URLs are resolved against
  /// [ClientOptions.baseUrl]. Pass [json] to encode a JSON request body and set
  /// the content type automatically, or pass [body] for raw body inputs accepted
  /// by [Body.from].
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
    final requestBody = resolveRequestBody(
      body: body,
      json: json,
      jsonOmitted: _jsonOmitted,
    );
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

  /// Sends a request and captures success or failure in a [Result].
  ///
  /// This is the no-throw form of [request].
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

  /// Sends a `GET` request.
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

  /// Sends a `POST` request.
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

  /// Sends a `PUT` request.
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

  /// Sends a `PATCH` request.
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

  /// Sends a `DELETE` request.
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

  /// Sends a `HEAD` request.
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

  /// Sends an `OPTIONS` request.
  ///
  /// The method name avoids colliding with the [options] parameter used by the
  /// other request helpers.
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

  /// Sends a request and decodes the JSON response body.
  ///
  /// If [decoder] is provided, it maps the decoded JSON payload to [T].
  /// Otherwise the decoded payload is cast to [T]. Decode and mapping failures
  /// are reported as [DecodeError].
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

  Future<_ApplicationPipelineResult> _runApplicationPipeline(
    Request request,
    Context context,
  ) async {
    final middleware = <Middleware>[
      ...options.middleware,
      ...context.requestOptions.middleware,
    ];

    var reachedTerminal = false;
    final next = _buildPipeline(middleware, (nextRequest, nextContext) {
      reachedTerminal = true;
      if (_usesClientRedirects(nextContext)) {
        return _runRedirects(nextRequest, nextContext, (
          redirectRequest,
          redirectContext,
        ) {
          return _runOperation(redirectRequest, redirectContext);
        });
      }
      return _runOperation(nextRequest, nextContext);
    });
    final response = await next(request, context);
    return _ApplicationPipelineResult(
      response: response,
      reachedTerminal: reachedTerminal,
    );
  }

  Future<Response> _completeShortCircuitedResponse(
    Request request,
    Response response,
    Context context,
  ) {
    if (context.redirectPolicy.mode == RedirectMode.follow &&
        _isRedirectStatus(response.status)) {
      return _runRedirects(request, context, (
        redirectRequest,
        redirectContext,
      ) {
        return _runOperation(redirectRequest, redirectContext);
      }, firstResponse: response);
    }
    return Future.value(_withResponseTimeouts(response, request, context));
  }

  Future<Response> _applyResponsePolicies(
    Request request,
    Response response,
    Context context,
  ) async {
    if (_isRedirectBlocked(response, context)) {
      throw StatusError(
        response,
        request: request,
        message: 'Redirect blocked by RedirectPolicy.error.',
      );
    }

    if (!context.statusPolicy.accepts(response)) {
      final preview = await _previewStatusBody(response, context);
      emitEvent(
        context.onEvent,
        RequestEventType.statusFailed,
        request: request,
        attempt: context.attempt,
        response: preview.response,
      );
      throw StatusError(
        preview.response,
        request: request,
        bodyPreview: preview.bodyPreview,
      );
    }

    return response;
  }

  bool _usesClientRedirects(Context context) {
    return context.redirectPolicy.mode == RedirectMode.follow &&
        context.capability.name != 'web';
  }

  Future<Response> _runRedirects(
    Request request,
    Context context,
    Next next, {
    Response? firstResponse,
  }) async {
    var current = request;
    var redirected = false;
    var response = firstResponse;
    for (var redirects = 0; ; redirects++) {
      response ??= await next(current, _allowRedirectStatus(context));
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
      try {
        current = _redirectRequest(current, response, location);
      } on FormatException catch (_, trace) {
        throw StatusError(
          response,
          request: current,
          message: 'Redirect response has an invalid Location header.',
          trace: trace,
        );
      }
      redirected = true;
      response = null;
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
          final retryContext = attemptContext.copyWith(
            signal: context.signal,
            clearSignal: context.signal == null,
          );
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
            response: preview.response,
          );
          throw StatusError(
            preview.response,
            request: attemptRequest,
            bodyPreview: preview.bodyPreview,
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
          final retryContext = attemptContext.copyWith(
            signal: context.signal,
            clearSignal: context.signal == null,
          );
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

  Response _withResponseTimeouts(
    Response response,
    Request request,
    Context context,
  ) {
    return _withTotalTimeout(
      _withReadTimeout(response, request, context),
      request,
      context,
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

  Future<_StatusBodyPreview> _previewStatusBody(
    Response response,
    Context context,
  ) async {
    final limit = context.clientOptions.errorBodyPreviewLimit;
    final body = response.body;
    if (limit <= 0 || body == null) {
      return _StatusBodyPreview(response: response);
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
          if (body.replayable) {
            await iterator.cancel();
            return _StatusBodyPreview(response: response);
          }
          return _StatusBodyPreview(
            response: response.copyWith(
              body: ResponseBody.stream(
                _restorePreviewStream(chunks, iterator),
                contentLength: body.contentLength,
              ),
            ),
          );
        }
      }

      final data = builder.takeBytes();
      final next = response.copyWith(body: ResponseBody.fromBytes(data));
      try {
        return _StatusBodyPreview(
          response: next,
          bodyPreview: utf8.decode(data),
        );
      } catch (_) {
        return _StatusBodyPreview(response: next);
      }
    } catch (_) {
      return _StatusBodyPreview(response: response);
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
}

final class _ApplicationPipelineResult {
  const _ApplicationPipelineResult({
    required this.response,
    required this.reachedTerminal,
  });

  final Response response;
  final bool reachedTerminal;
}

final class _DownstreamError {
  const _DownstreamError(this.error, this.trace);

  final Object error;
  final StackTrace trace;
}

/// The shared client used by [fetch] and [fetchResult].
///
/// This is useful for scripts and small programs. Call `client.close()` before
/// a short-lived process exits if it used the shared client.
final Client client = Client();

/// Sends a one-off request with the shared [client].
///
/// For reusable API clients, prefer creating a [Client] with explicit
/// [ClientOptions] and closing it when it is no longer needed.
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

/// Sends a one-off request and captures success or failure in a [Result].
///
/// This is the no-throw form of [fetch].
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
