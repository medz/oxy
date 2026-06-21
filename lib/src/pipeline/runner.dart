import 'dart:async';

import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import 'context.dart';
import 'events.dart';
import 'middleware.dart';

List<Middleware> combineMiddleware(
  List<Middleware> first,
  List<Middleware> second,
) {
  if (first.isEmpty && second.isEmpty) {
    return const <Middleware>[];
  }
  return <Middleware>[...first, ...second];
}

final class MiddlewareLifecycle {
  MiddlewareLifecycle(List<Middleware> middleware)
    : _middleware = List<Middleware>.unmodifiable(middleware);

  final List<Middleware> _middleware;

  bool get isEmpty => _middleware.isEmpty;

  Future<Request> onRequest(Request request, Context context) async {
    var current = request;
    for (final middleware in _middleware) {
      if (middleware is RequestTransformer) {
        current = await _runCapability<Request>(
          middleware,
          'onRequest',
          current,
          context,
          () => middleware.onRequest(current, context),
        );
      }
    }
    return current;
  }

  Future<Response?> resolve(Request request, Context context) async {
    for (final middleware in _middleware) {
      if (middleware is RequestResolver) {
        final response = await _runCapability<Response?>(
          middleware,
          'resolve',
          request,
          context,
          () => middleware.resolve(request, context),
        );
        if (response != null) {
          return response;
        }
      }
    }
    return null;
  }

  Future<Request> onAttempt(Request request, Context context) async {
    var current = request;
    for (final middleware in _middleware) {
      if (middleware is AttemptTransformer) {
        current = await _runCapability<Request>(
          middleware,
          'onAttempt',
          current,
          context,
          () => middleware.onAttempt(current, context),
        );
      }
    }
    return current;
  }

  Future<Response> onAttemptResponse(
    Request request,
    Response response,
    Context context,
  ) async {
    var current = response;
    for (var i = _middleware.length - 1; i >= 0; i--) {
      final middleware = _middleware[i];
      if (middleware is AttemptResponseHandler) {
        current = await _runCapability<Response>(
          middleware,
          'onAttemptResponse',
          request,
          context,
          () => middleware.onAttemptResponse(request, current, context),
          response: current,
        );
      }
    }
    return current;
  }

  Future<Response> onResponse(
    Request request,
    Response response,
    Context context,
  ) async {
    var current = response;
    for (var i = _middleware.length - 1; i >= 0; i--) {
      final middleware = _middleware[i];
      if (middleware is FinalResponseHandler) {
        current = await _runCapability<Response>(
          middleware,
          'onResponse',
          request,
          context,
          () => middleware.onResponse(request, current, context),
          response: current,
        );
      }
    }
    return current;
  }

  Future<void> onError(Request request, Object error, Context context) async {
    for (var i = _middleware.length - 1; i >= 0; i--) {
      final middleware = _middleware[i];
      if (middleware is FinalErrorHandler) {
        await _runCapability<void>(
          middleware,
          'onError',
          request,
          context,
          () => middleware.onError(request, error, context),
        );
      }
    }
  }

  Future<void> onFinally(Request request, Context context) async {
    for (var i = _middleware.length - 1; i >= 0; i--) {
      final middleware = _middleware[i];
      if (middleware is FinalFinallyHandler) {
        await _runCapability<void>(
          middleware,
          'onFinally',
          request,
          context,
          () => middleware.onFinally(request, context),
        );
      }
    }
  }

  Future<T> _runCapability<T>(
    Middleware middleware,
    String capability,
    Request request,
    Context context,
    FutureOr<T> Function() run, {
    Response? response,
  }) async {
    final detail = '${middleware.runtimeType}.$capability';
    emitEvent(
      context.onEvent,
      RequestEventType.middlewareStart,
      request: request,
      attempt: context.attempt,
      detail: detail,
    );

    try {
      final result = await run();
      emitEvent(
        context.onEvent,
        RequestEventType.middlewareEnd,
        request: request,
        attempt: context.attempt,
        response: result is Response ? result : response,
        detail: detail,
      );
      return result;
    } catch (error, trace) {
      if (error is RequestError) {
        emitEvent(
          context.onEvent,
          RequestEventType.middlewareEnd,
          request: request,
          attempt: context.attempt,
          error: error,
          detail: detail,
        );
        rethrow;
      }

      final middlewareError = MiddlewareError(
        middleware: detail,
        message: 'Middleware execution failed.',
        request: request,
        cause: error,
        trace: trace,
      );
      emitEvent(
        context.onEvent,
        RequestEventType.middlewareEnd,
        request: request,
        attempt: context.attempt,
        error: middlewareError,
        detail: detail,
      );
      throw middlewareError;
    }
  }
}
