import 'core/abort.dart';
import 'core/attributes.dart';
import 'core/headers.dart';
import 'pipeline/events.dart';
import 'pipeline/middleware.dart';
import 'policies.dart';
import 'transport/transport.dart';

typedef JsonMap = Map<String, Object?>;
typedef QueryMap = Map<String, Object?>;
typedef Decoder<T> = T Function(Object? value);
typedef ProgressCallback = void Function(TransferProgress progress);

final class TransferProgress {
  const TransferProgress({required this.transferred, required this.total});

  final int transferred;
  final int? total;

  double? get percent {
    final total = this.total;
    if (total == null || total == 0) {
      return null;
    }
    return transferred / total;
  }
}

final class ClientOptions {
  const ClientOptions({
    this.baseUrl,
    this.defaultHeaders,
    this.timeoutPolicy = const TimeoutPolicy(),
    this.retryPolicy = const RetryPolicy(),
    this.redirectPolicy = RedirectPolicy.follow,
    this.statusPolicy = StatusPolicy.throwOnError,
    this.middleware = const <Middleware>[],
    this.networkMiddleware = const <Middleware>[],
    this.hooks = const Hooks(),
    this.transport,
    this.keepAlive = true,
    this.userAgent = 'oxy/0.3.0',
    this.errorBodyPreviewLimit = 4096,
    this.attributes = const Attributes(),
    this.onEvent,
  });

  final Uri? baseUrl;
  final HeadersInit? defaultHeaders;
  final TimeoutPolicy timeoutPolicy;
  final RetryPolicy retryPolicy;
  final RedirectPolicy redirectPolicy;
  final StatusPolicy statusPolicy;
  final List<Middleware> middleware;
  final List<Middleware> networkMiddleware;
  final Hooks hooks;
  final Transport? transport;
  final bool keepAlive;
  final String userAgent;
  final int errorBodyPreviewLimit;
  final Attributes attributes;
  final EventSink? onEvent;

  ClientOptions copyWith({
    Uri? baseUrl,
    HeadersInit? defaultHeaders,
    TimeoutPolicy? timeoutPolicy,
    RetryPolicy? retryPolicy,
    RedirectPolicy? redirectPolicy,
    StatusPolicy? statusPolicy,
    List<Middleware>? middleware,
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

final class RequestOptions {
  const RequestOptions({
    this.headers,
    this.query,
    this.timeoutPolicy,
    this.retryPolicy,
    this.redirectPolicy,
    this.statusPolicy,
    this.middleware = const <Middleware>[],
    this.networkMiddleware = const <Middleware>[],
    this.hooks,
    this.signal,
    this.onSendProgress,
    this.onReceiveProgress,
    this.attributes = const Attributes(),
  });

  final HeadersInit? headers;
  final QueryMap? query;
  final TimeoutPolicy? timeoutPolicy;
  final RetryPolicy? retryPolicy;
  final RedirectPolicy? redirectPolicy;
  final StatusPolicy? statusPolicy;
  final List<Middleware> middleware;
  final List<Middleware> networkMiddleware;
  final Hooks? hooks;
  final AbortSignal? signal;
  final ProgressCallback? onSendProgress;
  final ProgressCallback? onReceiveProgress;
  final Attributes attributes;

  RequestOptions copyWith({
    HeadersInit? headers,
    QueryMap? query,
    TimeoutPolicy? timeoutPolicy,
    RetryPolicy? retryPolicy,
    RedirectPolicy? redirectPolicy,
    StatusPolicy? statusPolicy,
    List<Middleware>? middleware,
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
