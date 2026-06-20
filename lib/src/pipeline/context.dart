import '../core/abort.dart';
import '../core/attributes.dart';
import '../core/request.dart';
import '../options.dart';
import '../policies.dart';
import '../transport/capability.dart';
import 'events.dart';

/// Per-request execution context passed through middleware and transports.
///
/// The context contains the resolved policies, platform capability, current
/// retry attempt, attributes, cancellation signal, and event sink.
final class Context {
  const Context({
    required this.clientOptions,
    required this.requestOptions,
    required this.timeoutPolicy,
    required this.retryPolicy,
    required this.redirectPolicy,
    required this.statusPolicy,
    required this.capability,
    required this.attributes,
    required this.createdAt,
    required this.attempt,
    this.signal,
    this.onEvent,
  });

  /// Client-level defaults.
  final ClientOptions clientOptions;

  /// Request-level overrides.
  final RequestOptions requestOptions;

  /// Resolved timeout policy.
  final TimeoutPolicy timeoutPolicy;

  /// Resolved retry policy.
  final RetryPolicy retryPolicy;

  /// Resolved redirect policy.
  final RedirectPolicy redirectPolicy;

  /// Resolved status policy.
  final StatusPolicy statusPolicy;

  /// Capabilities of the active transport.
  final PlatformCapability capability;

  /// Merged client, request, and send attributes.
  final Attributes attributes;

  /// When the logical request started.
  final DateTime createdAt;

  /// Zero-based network attempt.
  final int attempt;

  /// Cancellation signal for this attempt.
  final AbortSignal? signal;

  /// Event sink for request lifecycle events.
  final EventSink? onEvent;

  /// Upload progress callback for this request.
  ProgressCallback? get onSendProgress => requestOptions.onSendProgress;

  /// Download progress callback for this request.
  ProgressCallback? get onReceiveProgress => requestOptions.onReceiveProgress;

  /// The attribute value for [key].
  T? attribute<T extends Object>(AttributeKey<T> key) => attributes.get(key);

  /// Creates a copy with selected execution values replaced.
  Context copyWith({
    RequestOptions? requestOptions,
    TimeoutPolicy? timeoutPolicy,
    RetryPolicy? retryPolicy,
    RedirectPolicy? redirectPolicy,
    StatusPolicy? statusPolicy,
    PlatformCapability? capability,
    Attributes? attributes,
    int? attempt,
    AbortSignal? signal,
    bool clearSignal = false,
    EventSink? onEvent,
  }) {
    assert(!clearSignal || signal == null, 'clearSignal and signal conflict');
    return Context(
      clientOptions: clientOptions,
      requestOptions: requestOptions ?? this.requestOptions,
      timeoutPolicy: timeoutPolicy ?? this.timeoutPolicy,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      redirectPolicy: redirectPolicy ?? this.redirectPolicy,
      statusPolicy: statusPolicy ?? this.statusPolicy,
      capability: capability ?? this.capability,
      attributes: attributes ?? this.attributes,
      createdAt: createdAt,
      attempt: attempt ?? this.attempt,
      signal: clearSignal ? null : signal ?? this.signal,
      onEvent: onEvent ?? this.onEvent,
    );
  }

  /// Emits a request lifecycle event through [onEvent].
  void emit(
    RequestEventType type,
    Request request, {
    Object? error,
    String? detail,
  }) {
    emitEvent(
      onEvent,
      type,
      request: request,
      attempt: attempt,
      error: error,
      detail: detail,
    );
  }
}
