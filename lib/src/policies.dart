import 'dart:math';

import 'core/request.dart';
import 'core/response.dart';

final class TimeoutPolicy {
  const TimeoutPolicy({
    this.connect = const Duration(seconds: 10),
    this.send,
    this.firstByte,
    this.read,
    this.total = const Duration(seconds: 30),
  });

  final Duration? connect;
  final Duration? send;
  final Duration? firstByte;
  final Duration? read;
  final Duration? total;
}

final class StatusPolicy {
  const StatusPolicy({this.enabled = true, this.accept});

  static const StatusPolicy throwOnError = StatusPolicy();
  static const StatusPolicy returnResponse = StatusPolicy(enabled: false);

  final bool enabled;
  final bool Function(Response response)? accept;

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

  final int maxRetries;
  final bool idempotentMethodsOnly;
  final Set<int> retryableStatusCodes;
  final Duration baseDelay;
  final Duration maxDelay;
  final double jitterRatio;
  final bool respectRetryAfter;

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

  bool shouldRetryResponse(Response response) {
    return retryableStatusCodes.contains(response.status);
  }

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

    final date = _parseHttpDate(value.trim()) ?? DateTime.tryParse(value);
    if (date == null) {
      return null;
    }

    final delta = date.toUtc().difference(DateTime.now().toUtc());
    return delta.isNegative ? Duration.zero : delta;
  }

  DateTime? _parseHttpDate(String value) {
    final match = RegExp(
      r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) '
      r'(\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }

    final month = _httpMonths[match.group(2)!.toLowerCase()];
    if (month == null) {
      return null;
    }

    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }
}

const Map<String, int> _httpMonths = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

enum RedirectMode { follow, manual, error }

final class RedirectPolicy {
  const RedirectPolicy({required this.mode, this.maxRedirects = 20})
    : assert(maxRedirects >= 0, 'maxRedirects must be >= 0');

  static const RedirectPolicy follow = RedirectPolicy(
    mode: RedirectMode.follow,
  );
  static const RedirectPolicy manual = RedirectPolicy(
    mode: RedirectMode.manual,
  );
  static const RedirectPolicy error = RedirectPolicy(mode: RedirectMode.error);

  final RedirectMode mode;
  final int maxRedirects;
}
