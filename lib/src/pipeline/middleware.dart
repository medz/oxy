import 'dart:async';

import '../core/request.dart';
import '../core/response.dart';
import 'context.dart';

/// Marker interface for middleware lifecycle capabilities.
///
/// Implement one or more capability interfaces to participate in the request
/// lifecycle. Oxy schedules each capability at the phase where it belongs.
abstract interface class Middleware {}

/// Mutates or observes the logical request before cache resolution or network
/// attempts begin.
abstract interface class RequestTransformer implements Middleware {
  /// Returns the request that should continue through the pipeline.
  FutureOr<Request> onRequest(Request request, Context context);
}

/// Resolves a logical request without reaching the transport.
abstract interface class RequestResolver implements Middleware {
  /// Returns a response to short-circuit the request, or `null` to continue.
  FutureOr<Response?> resolve(Request request, Context context);
}

/// Mutates or observes a single transport attempt.
abstract interface class AttemptTransformer implements Middleware {
  /// Returns the request that should be sent for this attempt.
  FutureOr<Request> onAttempt(Request request, Context context);
}

/// Handles the raw response from a single transport attempt before retry,
/// redirect, and final status policies run.
abstract interface class AttemptResponseHandler implements Middleware {
  /// Returns the response that should continue attempt processing.
  FutureOr<Response> onAttemptResponse(
    Request request,
    Response response,
    Context context,
  );
}

/// Handles the final successful response for a logical request.
abstract interface class FinalResponseHandler implements Middleware {
  /// Returns the response that should be delivered to hooks and callers.
  FutureOr<Response> onResponse(
    Request request,
    Response response,
    Context context,
  );
}

/// Observes a final failure for a logical request.
abstract interface class FinalErrorHandler implements Middleware {
  /// Called before client error hooks when request processing fails.
  FutureOr<void> onError(Request request, Object error, Context context);
}

/// Observes the end of a logical request.
abstract interface class FinalFinallyHandler implements Middleware {
  /// Called once request processing has finished.
  FutureOr<void> onFinally(Request request, Context context);
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

  /// Called before lifecycle middleware.
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
