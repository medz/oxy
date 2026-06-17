import 'request.dart';
import 'response.dart';

enum TimeoutPhase { connect, send, firstByte, read, total }

sealed class RequestError implements Exception {
  const RequestError(
    this.message, {
    this.request,
    this.response,
    this.cause,
    this.trace,
    this.sent = false,
    this.retryable = false,
  });

  final String message;
  final Request? request;
  final Response? response;
  final Object? cause;
  final StackTrace? trace;
  final bool sent;
  final bool retryable;

  @override
  String toString() => '$runtimeType: $message';
}

final class NetworkError extends RequestError {
  const NetworkError(
    super.message, {
    super.request,
    super.cause,
    super.trace,
    super.sent,
    super.retryable = true,
  });
}

final class TimeoutError extends RequestError {
  const TimeoutError({
    required this.phase,
    required this.duration,
    super.request,
    super.cause,
    super.trace,
    super.sent,
    super.retryable = true,
  }) : super('Timeout during $phase after $duration');

  final TimeoutPhase phase;
  final Duration duration;
}

final class CancelError extends RequestError {
  CancelError({this.reason, super.request, super.trace, super.sent})
    : super('Request cancelled', cause: reason, retryable: false);

  final Object? reason;
}

final class StatusError extends RequestError {
  StatusError(
    this.statusResponse, {
    super.request,
    String? message,
    this.bodyPreview,
    super.trace,
  }) : super(
         message ??
             'HTTP ${statusResponse.status} ${statusResponse.statusText}',
         response: statusResponse,
         sent: true,
         retryable: false,
       );

  final Response statusResponse;
  final String? bodyPreview;
}

final class DecodeError extends RequestError {
  const DecodeError(super.message, {super.response, super.cause, super.trace});
}

final class PolicyError extends RequestError {
  const PolicyError(super.message, {super.request, super.cause, super.trace});
}

final class RetryError extends RequestError {
  const RetryError({
    required this.attempts,
    this.lastError,
    this.lastResponse,
    super.request,
    super.trace,
  }) : super(
         'Retry exhausted after $attempts attempts',
         response: lastResponse,
         cause: lastError,
         sent: true,
         retryable: false,
       );

  final int attempts;
  final Object? lastError;
  final Response? lastResponse;
}

final class MiddlewareError extends RequestError {
  const MiddlewareError({
    required this.middleware,
    required String message,
    super.request,
    super.cause,
    super.trace,
  }) : super(message);

  final String middleware;
}

final class BodyStateError extends RequestError {
  const BodyStateError(super.message, {super.request, super.cause});
}

final class BodyTooLargeError extends RequestError {
  const BodyTooLargeError({required this.limit, super.request, super.response})
    : super('Body exceeded configured limit of $limit bytes.');

  final int limit;
}
