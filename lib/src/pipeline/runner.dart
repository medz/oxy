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

Next buildMiddlewarePipeline(List<Middleware> middleware, Next terminal) {
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

final class _DownstreamError {
  const _DownstreamError(this.error, this.trace);

  final Object error;
  final StackTrace trace;
}
