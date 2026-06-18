import '../core/request.dart';
import '../core/response.dart';

typedef EventSink = void Function(RequestEvent event);

enum RequestEventType {
  start,
  prepared,
  middlewareStart,
  middlewareEnd,
  attemptStart,
  attemptEnd,
  retryScheduled,
  retrySkipped,
  statusFailed,
  complete,
}

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

  final RequestEventType type;
  final Request request;
  final int attempt;
  final DateTime timestamp;
  final Response? response;
  final Object? error;
  final String? detail;
}

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
