import 'dart:async';

import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/events.dart';

bool shouldRetryResponse(Request request, Response response, Context context) {
  final policy = context.retryPolicy;
  if (policy.maxRetries <= 0 ||
      !policy.allowsMethod(request) ||
      request.body?.replayable == false) {
    return false;
  }
  return policy.shouldRetryResponse(response);
}

bool shouldRetryError(Request request, Object error, Context context) {
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

Future<void> beforeRetry(
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

Future<void> waitRetryDelay(Duration delay, Context context) {
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
