import 'dart:async';

import '../core/request.dart';
import '../core/response.dart';
import 'context.dart';

/// Continues request processing from middleware.
typedef Next = Future<Response> Function(Request request, Context context);

/// Intercepts a request before or around the next pipeline step.
///
/// Application middleware runs once per logical request. Network middleware
/// runs once per network attempt, including retries and redirects.
abstract interface class Middleware {
  /// Handles [request] and either returns a [Response] or calls [next].
  Future<Response> intercept(Request request, Context context, Next next);
}

/// Hook called with a request and context.
typedef HookCallback =
    FutureOr<void> Function(Request request, Context context);

/// Hook called with a response that may be replaced.
typedef ResponseHookCallback =
    FutureOr<Response> Function(
      Request request,
      Response response,
      Context context,
    );

/// Hook called when request processing fails.
typedef ErrorHookCallback =
    FutureOr<void> Function(Request request, Object error, Context context);

/// Hook called before a retry delay.
typedef RetryHookCallback =
    FutureOr<void> Function(
      Request request,
      Object? error,
      Response? response,
      Duration delay,
      Context context,
    );

/// Optional lifecycle callbacks for request processing.
final class Hooks {
  const Hooks({
    this.onRequest,
    this.onResponse,
    this.onError,
    this.onRetry,
    this.onFinally,
  });

  /// Called before application middleware.
  final HookCallback? onRequest;

  /// Called after response policies and before the final response is returned.
  final ResponseHookCallback? onResponse;

  /// Called when request processing fails.
  final ErrorHookCallback? onError;

  /// Called before a retry delay.
  final RetryHookCallback? onRetry;

  /// Called once request processing has finished.
  final HookCallback? onFinally;

  /// Merges [other] over this hook set.
  Hooks merge(Hooks? other) {
    if (other == null) {
      return this;
    }

    return Hooks(
      onRequest: other.onRequest ?? onRequest,
      onResponse: other.onResponse ?? onResponse,
      onError: other.onError ?? onError,
      onRetry: other.onRetry ?? onRetry,
      onFinally: other.onFinally ?? onFinally,
    );
  }
}
