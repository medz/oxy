import '../core/abort.dart';
import '../core/attributes.dart';
import '../core/request.dart';
import '../options.dart';
import '../policies.dart';
import '../transport/capability.dart';
import 'events.dart';

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

  final ClientOptions clientOptions;
  final RequestOptions requestOptions;
  final TimeoutPolicy timeoutPolicy;
  final RetryPolicy retryPolicy;
  final RedirectPolicy redirectPolicy;
  final StatusPolicy statusPolicy;
  final PlatformCapability capability;
  final Attributes attributes;
  final DateTime createdAt;
  final int attempt;
  final AbortSignal? signal;
  final EventSink? onEvent;

  ProgressCallback? get onSendProgress => requestOptions.onSendProgress;
  ProgressCallback? get onReceiveProgress => requestOptions.onReceiveProgress;

  T? attribute<T extends Object>(AttributeKey<T> key) => attributes.get(key);

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
