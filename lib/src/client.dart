import 'dart:async';
import 'dart:math';

import 'core/abort.dart';
import 'core/errors.dart';
import 'core/headers.dart';
import 'core/request.dart';
import 'core/response.dart';
import 'core/result.dart';
import 'client/redirects.dart';
import 'client/request_resolution.dart';
import 'client/response_policies.dart';
import 'client/retry.dart';
import 'client/timeouts.dart';
import 'options.dart';
import 'pipeline/context.dart';
import 'pipeline/events.dart';
import 'pipeline/middleware.dart';
import 'pipeline/runner.dart';
import 'policies.dart';
import 'transport/default_transport.dart';
import 'transport/transport.dart';

const Object _jsonOmitted = Object();

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
    final timeoutSignal = needsInternalSignal(context.timeoutPolicy)
        ? linkedSignal(context.signal)
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
        final policyResponse = await applyResponsePolicies(
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
    final middleware = combineMiddleware(
      options.middleware,
      context.requestOptions.middleware,
    );

    var reachedTerminal = false;
    final next = buildMiddlewarePipeline(middleware, (
      nextRequest,
      nextContext,
    ) {
      reachedTerminal = true;
      if (usesClientRedirects(nextContext)) {
        return runRedirects(nextRequest, nextContext, (
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
        isRedirectStatus(response.status)) {
      return runRedirects(request, context, (redirectRequest, redirectContext) {
        return _runOperation(redirectRequest, redirectContext);
      }, firstResponse: response);
    }
    return Future.value(withResponseTimeouts(response, request, context));
  }

  Future<Response> _runOperation(Request request, Context context) async {
    final retryPolicy = context.retryPolicy;
    Object? lastError;
    Response? lastResponse;

    for (var attempt = 0; ; attempt++) {
      final attemptSignal = linkedSignal(context.signal);
      final attemptContext = context.copyWith(
        attempt: attempt,
        signal: attemptSignal,
      );
      final attemptRequest = sanitizeRedirectHeaders(request);

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
        response = withReadTimeout(response, attemptRequest, attemptContext);
        response = withTotalTimeout(response, attemptRequest, attemptContext);

        emitEvent(
          attemptContext.onEvent,
          RequestEventType.attemptEnd,
          request: attemptRequest,
          attempt: attempt,
          response: response,
        );

        if (isRedirectBlocked(response, attemptContext)) {
          throw StatusError(
            response,
            request: attemptRequest,
            message: 'Redirect blocked by RedirectPolicy.error.',
          );
        }

        if (shouldRetryResponse(attemptRequest, response, attemptContext)) {
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
          await beforeRetry(
            attemptRequest,
            retryContext,
            null,
            response,
            delay,
          );
          await waitRetryDelay(delay, retryContext);
          continue;
        }

        return await applyResponsePolicies(
          attemptRequest,
          response,
          attemptContext,
        );
      } catch (error, trace) {
        final normalized = _normalizeError(
          error,
          trace,
          attemptRequest,
          attemptContext,
        );
        lastError = normalized;

        if (shouldRetryError(attemptRequest, normalized, attemptContext)) {
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
          await beforeRetry(
            attemptRequest,
            retryContext,
            normalized,
            null,
            delay,
          );
          await waitRetryDelay(delay, retryContext);
          continue;
        }

        throw normalized;
      }
    }
  }

  Future<Response> _runNetworkPipeline(Request request, Context context) {
    final middleware = combineMiddleware(
      options.networkMiddleware,
      context.requestOptions.networkMiddleware,
    );

    final operation = buildMiddlewarePipeline(middleware, (
      nextRequest,
      nextContext,
    ) {
      return _transport.send(sanitizeRedirectHeaders(nextRequest), nextContext);
    })(request, context);
    return operation;
  }

  void _throwIfAborted(AbortSignal? signal, Request request) {
    if (signal?.aborted == true) {
      throw CancelError(reason: signal?.reason, request: request);
    }
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
}

final class _ApplicationPipelineResult {
  const _ApplicationPipelineResult({
    required this.response,
    required this.reachedTerminal,
  });

  final Response response;
  final bool reachedTerminal;
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
