import '../core/request.dart';
import '../core/response.dart';

/// Receives request lifecycle events.
typedef EventSink = void Function(RequestEvent event);

/// Event types emitted while a request moves through the client.
enum RequestEventType {
  /// The logical request started.
  start,

  /// The request was resolved against client and request options.
  prepared,

  /// A middleware started.
  middlewareStart,

  /// A middleware completed.
  middlewareEnd,

  /// A network attempt started.
  attemptStart,

  /// A network attempt completed with a response.
  attemptEnd,

  /// A retry was scheduled.
  retryScheduled,

  /// A retry was skipped.
  retrySkipped,

  /// A response failed status validation.
  statusFailed,

  /// The logical request completed successfully.
  complete,
}

/// A request lifecycle event.
final class RequestEvent {
  const RequestEvent({
    required this.type,
    required this.request,
    required this.attempt,
    required this.timestamp,
    this.response,
    this.error,
    this.detail,
  });

  /// The event type.
  final RequestEventType type;

  /// The request associated with the event.
  final Request request;

  /// The zero-based attempt associated with the event.
  final int attempt;

  /// When the event was emitted.
  final DateTime timestamp;

  /// The response associated with the event, when available.
  final Response? response;

  /// The error associated with the event, when available.
  final Object? error;

  /// Additional event detail, when available.
  final String? detail;
}

/// Emits a [RequestEvent] to [sink] when [sink] is not `null`.
void emitEvent(
  EventSink? sink,
  RequestEventType type, {
  required Request request,
  required int attempt,
  Response? response,
  Object? error,
  String? detail,
}) {
  sink?.call(
    RequestEvent(
      type: type,
      request: request,
      attempt: attempt,
      timestamp: DateTime.now().toUtc(),
      response: response,
      error: error,
      detail: detail,
    ),
  );
}
