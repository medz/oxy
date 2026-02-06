import 'package:ht/ht.dart';

enum TimeoutPhase { connect, request }

sealed class OxyException implements Exception {
  const OxyException(this.message, {this.cause, this.trace});

  final String message;
  final Object? cause;
  final StackTrace? trace;

  @override
  String toString() {
    return '$runtimeType: $message';
  }
}

class OxyHttpException extends OxyException {
  OxyHttpException(this.response, {String? message, Object? cause, super.trace})
    : super(
        message ??
            'HTTP ${response.status} ${response.statusText}: ${response.url ?? 'unknown url'}',
        cause: cause,
      );

  final Response response;
}

class OxyNetworkException extends OxyException {
  const OxyNetworkException(super.message, {super.cause, super.trace});
}

class OxyTimeoutException extends OxyException {
  const OxyTimeoutException({
    required this.phase,
    required this.duration,
    Object? cause,
    StackTrace? trace,
  }) : super(
         'Timeout during $phase after $duration',
         cause: cause,
         trace: trace,
       );

  final TimeoutPhase phase;
  final Duration duration;
}

class OxyCancelledException extends OxyException {
  const OxyCancelledException({this.reason, StackTrace? trace})
    : super('Request cancelled', cause: reason, trace: trace);

  final Object? reason;
}

class OxyDecodeException extends OxyException {
  const OxyDecodeException(super.message, {super.cause, super.trace});
}

class OxyRetryExhaustedException extends OxyException {
  const OxyRetryExhaustedException({
    required this.attempts,
    this.lastError,
    this.lastResponse,
    StackTrace? trace,
  }) : super(
         'Retry exhausted after $attempts attempts',
         cause: lastError,
         trace: trace,
       );

  final int attempts;
  final Object? lastError;
  final Response? lastResponse;
}

class OxyMiddlewareException extends OxyException {
  const OxyMiddlewareException({
    required this.middleware,
    required String message,
    Object? cause,
    StackTrace? trace,
  }) : super(message, cause: cause, trace: trace);

  final String middleware;
}
