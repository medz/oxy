import 'request.dart';
import 'response.dart';

/// The request phase that exceeded a configured timeout.
enum TimeoutPhase { connect, send, firstByte, read, total }

/// Base type for errors produced by Oxy request processing.
///
/// Subtypes carry the request, response, original cause, stack trace, and
/// retry metadata when that context is available.
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

  /// Human-readable error message.
  final String message;

  /// The request associated with this error, when available.
  final Request? request;

  /// The response associated with this error, when available.
  final Response? response;

  /// The original error that caused this failure, when available.
  final Object? cause;

  /// The original stack trace, when available.
  final StackTrace? trace;

  /// Whether the request was sent before the error occurred.
  final bool sent;

  /// Whether this error is retryable by policy.
  final bool retryable;

  @override
  String toString() => '$runtimeType: $message';
}

/// A transport or network failure.
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

/// A request timeout.
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

  /// The request phase that timed out.
  final TimeoutPhase phase;

  /// The configured timeout duration.
  final Duration duration;
}

/// A request cancellation.
final class CancelError extends RequestError {
  CancelError({this.reason, super.request, super.trace, super.sent})
    : super('Request cancelled', cause: reason, retryable: false);

  /// The cancellation reason supplied by the caller.
  final Object? reason;
}

/// A response rejected by status or redirect policy.
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

  /// The rejected response.
  final Response statusResponse;

  /// A bounded UTF-8 body preview, when available.
  final String? bodyPreview;
}

/// A response decoding or mapping failure.
final class DecodeError extends RequestError {
  const DecodeError(super.message, {super.response, super.cause, super.trace});
}

/// A configuration or policy failure before a request is sent.
final class PolicyError extends RequestError {
  const PolicyError(super.message, {super.request, super.cause, super.trace});
}

/// A retry loop that exhausted all attempts.
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

  /// Total number of attempts, including the first attempt.
  final int attempts;

  /// The last retryable error, when the final failure was an error.
  final Object? lastError;

  /// The last retryable response, when the final failure was a response.
  final Response? lastResponse;
}

/// A middleware failure with middleware context.
final class MiddlewareError extends RequestError {
  const MiddlewareError({
    required this.middleware,
    required String message,
    super.request,
    super.cause,
    super.trace,
  }) : super(message);

  /// The middleware label associated with the failure.
  final String middleware;
}

/// A body stream was used in an invalid state.
final class BodyStateError extends RequestError {
  const BodyStateError(super.message, {super.request, super.cause});
}

/// A body exceeded a configured byte limit while being read.
final class BodyTooLargeError extends RequestError {
  const BodyTooLargeError({required this.limit, super.request, super.response})
    : super('Body exceeded configured limit of $limit bytes.');

  /// The configured byte limit.
  final int limit;
}
