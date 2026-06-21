import 'dart:async';

import '../core/errors.dart';
import '../core/request.dart';
import '../pipeline/context.dart';

Object normalizeRequestError(
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
