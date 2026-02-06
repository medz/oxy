import 'dart:async';

import 'package:ht/ht.dart';

import 'abort.dart';
import 'cookie.dart';

typedef JsonMap = Map<String, Object?>;
typedef QueryMap = Map<String, Object?>;
typedef Decoder<T> = T Function(Object? value);
typedef ProgressCallback = void Function(TransferProgress progress);

enum RedirectPolicy { follow, manual, error }

class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 2,
    this.idempotentMethodsOnly = true,
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.baseDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 2),
  }) : assert(maxRetries >= 0, 'maxRetries must be >= 0');

  final int maxRetries;
  final bool idempotentMethodsOnly;
  final Set<int> retryableStatusCodes;
  final Duration baseDelay;
  final Duration maxDelay;

  RetryPolicy copyWith({
    int? maxRetries,
    bool? idempotentMethodsOnly,
    Set<int>? retryableStatusCodes,
    Duration? baseDelay,
    Duration? maxDelay,
  }) {
    return RetryPolicy(
      maxRetries: maxRetries ?? this.maxRetries,
      idempotentMethodsOnly:
          idempotentMethodsOnly ?? this.idempotentMethodsOnly,
      retryableStatusCodes: retryableStatusCodes ?? this.retryableStatusCodes,
      baseDelay: baseDelay ?? this.baseDelay,
      maxDelay: maxDelay ?? this.maxDelay,
    );
  }
}

class TransferProgress {
  const TransferProgress({required this.transferred, required this.total});

  final int transferred;
  final int? total;

  double? get percent {
    if (total == null || total == 0) {
      return null;
    }

    return transferred / total!;
  }
}

typedef Next =
    Future<Response> Function(Request request, RequestOptions options);

abstract interface class OxyMiddleware {
  Future<Response> intercept(
    Request request,
    RequestOptions options,
    Next next,
  );
}

class RequestOptions {
  const RequestOptions({
    this.headers,
    this.query,
    this.connectTimeout,
    this.requestTimeout,
    this.signal,
    this.redirectPolicy,
    this.maxRedirects,
    this.keepAlive,
    this.retryPolicy,
    this.throwOnHttpError,
    this.middleware = const [],
    this.onSendProgress,
    this.onReceiveProgress,
    this.extra = const {},
  });

  final Headers? headers;
  final QueryMap? query;
  final Duration? connectTimeout;
  final Duration? requestTimeout;
  final AbortSignal? signal;
  final RedirectPolicy? redirectPolicy;
  final int? maxRedirects;
  final bool? keepAlive;
  final RetryPolicy? retryPolicy;
  final bool? throwOnHttpError;
  final List<OxyMiddleware> middleware;
  final ProgressCallback? onSendProgress;
  final ProgressCallback? onReceiveProgress;
  final Map<String, Object?> extra;

  RequestOptions copyWith({
    Headers? headers,
    QueryMap? query,
    Duration? connectTimeout,
    Duration? requestTimeout,
    AbortSignal? signal,
    RedirectPolicy? redirectPolicy,
    int? maxRedirects,
    bool? keepAlive,
    RetryPolicy? retryPolicy,
    bool? throwOnHttpError,
    List<OxyMiddleware>? middleware,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    Map<String, Object?>? extra,
  }) {
    return RequestOptions(
      headers: headers ?? this.headers,
      query: query ?? this.query,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      signal: signal ?? this.signal,
      redirectPolicy: redirectPolicy ?? this.redirectPolicy,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      keepAlive: keepAlive ?? this.keepAlive,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      throwOnHttpError: throwOnHttpError ?? this.throwOnHttpError,
      middleware: middleware ?? this.middleware,
      onSendProgress: onSendProgress ?? this.onSendProgress,
      onReceiveProgress: onReceiveProgress ?? this.onReceiveProgress,
      extra: extra ?? this.extra,
    );
  }
}

class OxyConfig {
  const OxyConfig({
    this.baseUrl,
    this.defaultHeaders,
    this.connectTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 30),
    this.redirectPolicy = RedirectPolicy.follow,
    this.maxRedirects = 5,
    this.keepAlive = false,
    this.retryPolicy = const RetryPolicy(),
    this.throwOnHttpError = true,
    this.cookieJar,
    this.middleware = const [],
    this.userAgent = 'oxy/0.1.0',
  }) : assert(maxRedirects >= 0, 'maxRedirects must be >= 0');

  final Uri? baseUrl;
  final Headers? defaultHeaders;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final RedirectPolicy redirectPolicy;
  final int maxRedirects;
  final bool keepAlive;
  final RetryPolicy retryPolicy;
  final bool throwOnHttpError;
  final CookieJar? cookieJar;
  final List<OxyMiddleware> middleware;
  final String userAgent;

  OxyConfig copyWith({
    Uri? baseUrl,
    Headers? defaultHeaders,
    Duration? connectTimeout,
    Duration? requestTimeout,
    RedirectPolicy? redirectPolicy,
    int? maxRedirects,
    bool? keepAlive,
    RetryPolicy? retryPolicy,
    bool? throwOnHttpError,
    CookieJar? cookieJar,
    List<OxyMiddleware>? middleware,
    String? userAgent,
  }) {
    return OxyConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      redirectPolicy: redirectPolicy ?? this.redirectPolicy,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      keepAlive: keepAlive ?? this.keepAlive,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      throwOnHttpError: throwOnHttpError ?? this.throwOnHttpError,
      cookieJar: cookieJar ?? this.cookieJar,
      middleware: middleware ?? this.middleware,
      userAgent: userAgent ?? this.userAgent,
    );
  }
}
