import 'dart:async';

import '../core/request.dart';
import '../core/response.dart';
import 'context.dart';

typedef Next = Future<Response> Function(Request request, Context context);

abstract interface class Middleware {
  Future<Response> intercept(Request request, Context context, Next next);
}

typedef HookCallback =
    FutureOr<void> Function(Request request, Context context);
typedef ResponseHookCallback =
    FutureOr<Response> Function(
      Request request,
      Response response,
      Context context,
    );
typedef ErrorHookCallback =
    FutureOr<void> Function(Request request, Object error, Context context);
typedef RetryHookCallback =
    FutureOr<void> Function(
      Request request,
      Object? error,
      Response? response,
      Duration delay,
      Context context,
    );

final class Hooks {
  const Hooks({
    this.onRequest,
    this.onResponse,
    this.onError,
    this.onRetry,
    this.onFinally,
  });

  final HookCallback? onRequest;
  final ResponseHookCallback? onResponse;
  final ErrorHookCallback? onError;
  final RetryHookCallback? onRetry;
  final HookCallback? onFinally;

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
