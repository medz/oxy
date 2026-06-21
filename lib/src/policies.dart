import 'dart:math';

import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'core/request.dart';
import 'core/response.dart';

/// Timeouts applied to phases of a request.
///
/// A `null` phase timeout disables that phase. [total] bounds the whole
/// logical request, including retries, redirects, middleware, and response body
/// reads performed through the returned [Response].
final class TimeoutPolicy {
  const TimeoutPolicy({
    this.connect = const Duration(seconds: 10),
    this.send,
    this.firstByte,
    this.read,
    this.total = const Duration(seconds: 30),
  });

  /// Maximum time to establish a native connection.
  final Duration? connect;

  /// Maximum time to send the request body.
  final Duration? send;

  /// Maximum time to receive the first response byte.
  final Duration? firstByte;

  /// Maximum idle time while reading response body chunks.
  final Duration? read;

  /// Maximum time for the whole logical request.
  final Duration? total;
}

/// Controls which HTTP responses are considered successful.
final class StatusPolicy {
  const StatusPolicy({this.enabled = true, this.accept});

  /// Throws `StatusError` for responses outside the 2xx range.
  static const StatusPolicy throwOnError = StatusPolicy();

  /// Returns every response without status validation.
  static const StatusPolicy returnResponse = StatusPolicy(enabled: false);

  /// Whether status validation is enabled.
  final bool enabled;

  /// Custom response acceptance predicate.
  final bool Function(Response response)? accept;

  /// Whether [response] should be returned instead of throwing `StatusError`.
  bool accepts(Response response) {
    if (!enabled) {
      return true;
    }
    final custom = accept;
    if (custom != null) {
      return custom(response);
    }
    return response.ok;
  }
}

/// Controls retry attempts for transient failures.
///
/// Oxy retries conservatively by default: idempotent methods only, selected
/// transient status codes, retryable request errors, and replayable request
/// bodies.
final class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 2,
    this.idempotentMethodsOnly = true,
    this.retryableStatusCodes = const <int>{408, 429, 500, 502, 503, 504},
    this.baseDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 2),
    this.jitterRatio = 0.2,
    this.respectRetryAfter = true,
  }) : assert(maxRetries >= 0, 'maxRetries must be >= 0'),
       assert(jitterRatio >= 0, 'jitterRatio must be >= 0');

  /// Maximum retries after the first attempt.
  final int maxRetries;

  /// Whether only idempotent methods may be retried.
  final bool idempotentMethodsOnly;

  /// Status codes that may be retried.
  final Set<int> retryableStatusCodes;

  /// Initial delay before retrying.
  final Duration baseDelay;

  /// Maximum exponential backoff delay.
  final Duration maxDelay;

  /// Fraction of random jitter applied around the computed delay.
  final double jitterRatio;

  /// Whether `Retry-After` response headers should override backoff.
  final bool respectRetryAfter;

  /// Whether [request] is allowed to retry by method.
  bool allowsMethod(Request request) {
    if (!idempotentMethodsOnly) {
      return true;
    }

    return const <String>{
      'GET',
      'HEAD',
      'OPTIONS',
      'PUT',
      'DELETE',
    }.contains(request.method.toUpperCase());
  }

  /// Whether [response] has a retryable status code.
  bool shouldRetryResponse(Response response) {
    return retryableStatusCodes.contains(response.status);
  }

  /// The delay before retrying [attempt].
  ///
  /// `attempt` is zero-based. When [response] has a valid `Retry-After` header
  /// and [respectRetryAfter] is `true`, that value wins over exponential
  /// backoff.
  Duration delayFor(int attempt, {Response? response, Random? random}) {
    assert(!baseDelay.isNegative, 'baseDelay must be >= 0');
    assert(!maxDelay.isNegative, 'maxDelay must be >= 0');

    final retryAfter = response == null || !respectRetryAfter
        ? null
        : _retryAfter(response);
    if (retryAfter != null) {
      return retryAfter;
    }

    final exponentialMs = baseDelay.inMilliseconds * (1 << attempt);
    final cappedMs = min(exponentialMs, maxDelay.inMilliseconds);
    final jitterSpan = (cappedMs * jitterRatio).round();
    final jitter = jitterSpan == 0
        ? 0
        : (random ?? Random()).nextInt(jitterSpan * 2 + 1) - jitterSpan;
    return Duration(milliseconds: max(0, cappedMs + jitter));
  }

  Duration? _retryAfter(Response response) {
    final value = response.headers.get('retry-after');
    if (value == null || value.isEmpty) {
      return null;
    }

    final seconds = int.tryParse(value.trim());
    if (seconds != null) {
      return Duration(seconds: max(0, seconds));
    }

    final date = _parseRetryAfterDate(value.trim());
    if (date == null) {
      return null;
    }

    final delta = date.toUtc().difference(DateTime.now().toUtc());
    return delta.isNegative ? Duration.zero : delta;
  }

  DateTime? _parseRetryAfterDate(String value) {
    try {
      return parseHttpDate(value);
    } on FormatException {
      return DateTime.tryParse(value);
    }
  }
}

/// Redirect handling behavior.
enum RedirectMode {
  /// Follow redirects in Oxy when the platform transport does not own them.
  follow,

  /// Return redirect responses to the caller.
  manual,

  /// Throw `StatusError` for redirect responses.
  error,
}

/// Controls redirect handling.
final class RedirectPolicy {
  const RedirectPolicy({required this.mode, this.maxRedirects = 20})
    : assert(maxRedirects >= 0, 'maxRedirects must be >= 0');

  /// Follows redirects up to [maxRedirects].
  static const RedirectPolicy follow = RedirectPolicy(
    mode: RedirectMode.follow,
  );

  /// Returns redirect responses without following them.
  static const RedirectPolicy manual = RedirectPolicy(
    mode: RedirectMode.manual,
  );

  /// Throws `StatusError` when a redirect response is encountered.
  static const RedirectPolicy error = RedirectPolicy(mode: RedirectMode.error);

  /// The redirect handling mode.
  final RedirectMode mode;

  /// Maximum number of redirects to follow.
  final int maxRedirects;
}
