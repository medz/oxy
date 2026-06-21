import 'core/abort.dart';
import 'core/attributes.dart';
import 'core/headers.dart';
import 'pipeline/events.dart';
import 'pipeline/middleware.dart';
import 'policies.dart';
import 'transport/transport.dart';

/// A JSON object represented by string keys and nullable JSON-like values.
typedef JsonMap = Map<String, Object?>;

/// Query parameters passed to request helpers.
///
/// Values are converted to strings by Oxy when the final URL is prepared.
typedef QueryMap = Map<String, Object?>;

/// Maps a decoded JSON payload to a typed value.
typedef Decoder<T> = T Function(Object? value);

/// Receives upload or download progress for a request.
typedef ProgressCallback = void Function(TransferProgress progress);

/// Progress reported while bytes are transferred.
final class TransferProgress {
  const TransferProgress({required this.transferred, required this.total});

  /// The number of bytes transferred so far.
  final int transferred;

  /// The total number of bytes, or `null` when the transport cannot know it.
  final int? total;

  /// The completed fraction, or `null` when [total] is not available.
  double? get percent {
    final total = this.total;
    if (total == null || total == 0) {
      return null;
    }
    return transferred / total;
  }
}

/// Defaults used by a `Client`.
///
/// These options are resolved once per request and can be overridden for a
/// single send with [RequestOptions].
final class ClientOptions {
  const ClientOptions({
    this.baseUrl,
    this.defaultHeaders,
    this.timeoutPolicy = const TimeoutPolicy(),
    this.retryPolicy = const RetryPolicy(),
    this.redirectPolicy = RedirectPolicy.follow,
    this.statusPolicy = StatusPolicy.throwOnError,
    this.middleware = const <Middleware>[],
    @Deprecated(
      'Use middleware with lifecycle-capable middleware instead. '
      'networkMiddleware will be removed before 1.0.',
    )
    this.networkMiddleware = const <Middleware>[],
    this.hooks = const Hooks(),
    this.transport,
    this.keepAlive = true,
    this.userAgent = 'oxy/0.3.0',
    this.errorBodyPreviewLimit = 4096,
    this.attributes = const Attributes(),
    this.onEvent,
  });

  /// The base URL used to resolve relative request URLs.
  final Uri? baseUrl;

  /// Headers added to every request unless overridden by the request.
  final HeadersInit? defaultHeaders;

  /// Timeout policy applied to every request by default.
  final TimeoutPolicy timeoutPolicy;

  /// Retry policy applied to retryable requests by default.
  final RetryPolicy retryPolicy;

  /// Redirect policy applied to every request by default.
  final RedirectPolicy redirectPolicy;

  /// Status validation policy applied to every response by default.
  final StatusPolicy statusPolicy;

  /// Middleware scheduled by lifecycle capabilities.
  final List<Middleware> middleware;

  /// Deprecated attempt-only middleware.
  @Deprecated(
    'Use middleware with lifecycle-capable middleware instead. '
    'networkMiddleware will be removed before 1.0.',
  )
  final List<Middleware> networkMiddleware;

  /// Lifecycle hooks applied to every request.
  final Hooks hooks;

  /// Custom transport used by the client, or `null` to use the platform default.
  final Transport? transport;

  /// Whether the native default transport should keep connections alive.
  final bool keepAlive;

  /// User agent sent by non-Web default transports.
  final String userAgent;

  /// Maximum number of response body bytes to include in `StatusError` previews.
  final int errorBodyPreviewLimit;

  /// Client-level attributes visible to middleware and transports.
  final Attributes attributes;

  /// Event sink for observing request lifecycle events.
  final EventSink? onEvent;

  /// Creates a copy with selected values replaced.
  ClientOptions copyWith({
    Uri? baseUrl,
    HeadersInit? defaultHeaders,
    TimeoutPolicy? timeoutPolicy,
    RetryPolicy? retryPolicy,
    RedirectPolicy? redirectPolicy,
    StatusPolicy? statusPolicy,
    List<Middleware>? middleware,
    @Deprecated(
      'Use middleware with lifecycle-capable middleware instead. '
      'networkMiddleware will be removed before 1.0.',
    )
    List<Middleware>? networkMiddleware,
    Hooks? hooks,
    Transport? transport,
    bool? keepAlive,
    String? userAgent,
    int? errorBodyPreviewLimit,
    Attributes? attributes,
    EventSink? onEvent,
  }) {
    return ClientOptions(
      baseUrl: baseUrl ?? this.baseUrl,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      timeoutPolicy: timeoutPolicy ?? this.timeoutPolicy,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      redirectPolicy: redirectPolicy ?? this.redirectPolicy,
      statusPolicy: statusPolicy ?? this.statusPolicy,
      middleware: middleware ?? this.middleware,
      networkMiddleware: networkMiddleware ?? this.networkMiddleware,
      hooks: hooks ?? this.hooks,
      transport: transport ?? this.transport,
      keepAlive: keepAlive ?? this.keepAlive,
      userAgent: userAgent ?? this.userAgent,
      errorBodyPreviewLimit:
          errorBodyPreviewLimit ?? this.errorBodyPreviewLimit,
      attributes: attributes ?? this.attributes,
      onEvent: onEvent ?? this.onEvent,
    );
  }
}

/// Per-request overrides.
///
/// Values set here take precedence over [ClientOptions] for a single request.
final class RequestOptions {
  const RequestOptions({
    this.headers,
    this.query,
    this.timeoutPolicy,
    this.retryPolicy,
    this.redirectPolicy,
    this.statusPolicy,
    this.middleware = const <Middleware>[],
    @Deprecated(
      'Use middleware with lifecycle-capable middleware instead. '
      'networkMiddleware will be removed before 1.0.',
    )
    this.networkMiddleware = const <Middleware>[],
    this.hooks,
    this.signal,
    this.onSendProgress,
    this.onReceiveProgress,
    this.attributes = const Attributes(),
  });

  /// Headers merged into the prepared request.
  final HeadersInit? headers;

  /// Query parameters merged into the prepared URL.
  final QueryMap? query;

  /// Timeout policy override.
  final TimeoutPolicy? timeoutPolicy;

  /// Retry policy override.
  final RetryPolicy? retryPolicy;

  /// Redirect policy override.
  final RedirectPolicy? redirectPolicy;

  /// Status validation policy override.
  final StatusPolicy? statusPolicy;

  /// Lifecycle middleware added to this request.
  final List<Middleware> middleware;

  /// Deprecated attempt-only middleware added to this request.
  @Deprecated(
    'Use middleware with lifecycle-capable middleware instead. '
    'networkMiddleware will be removed before 1.0.',
  )
  final List<Middleware> networkMiddleware;

  /// Lifecycle hook overrides.
  final Hooks? hooks;

  /// Cancellation signal for this request.
  final AbortSignal? signal;

  /// Upload progress callback.
  final ProgressCallback? onSendProgress;

  /// Download progress callback.
  final ProgressCallback? onReceiveProgress;

  /// Request-level attributes visible to middleware and transports.
  final Attributes attributes;

  /// Creates a copy with selected values replaced.
  RequestOptions copyWith({
    HeadersInit? headers,
    QueryMap? query,
    TimeoutPolicy? timeoutPolicy,
    RetryPolicy? retryPolicy,
    RedirectPolicy? redirectPolicy,
    StatusPolicy? statusPolicy,
    List<Middleware>? middleware,
    @Deprecated(
      'Use middleware with lifecycle-capable middleware instead. '
      'networkMiddleware will be removed before 1.0.',
    )
    List<Middleware>? networkMiddleware,
    Hooks? hooks,
    AbortSignal? signal,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    Attributes? attributes,
  }) {
    return RequestOptions(
      headers: headers ?? this.headers,
      query: query ?? this.query,
      timeoutPolicy: timeoutPolicy ?? this.timeoutPolicy,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      redirectPolicy: redirectPolicy ?? this.redirectPolicy,
      statusPolicy: statusPolicy ?? this.statusPolicy,
      middleware: middleware ?? this.middleware,
      networkMiddleware: networkMiddleware ?? this.networkMiddleware,
      hooks: hooks ?? this.hooks,
      signal: signal ?? this.signal,
      onSendProgress: onSendProgress ?? this.onSendProgress,
      onReceiveProgress: onReceiveProgress ?? this.onReceiveProgress,
      attributes: attributes ?? this.attributes,
    );
  }
}
