import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../transport/capability.dart';
import '../transport/transport.dart';

/// Handles requests sent through [MockTransport].
typedef MockResponder =
    Future<Response> Function(Request request, Context context);

/// Deterministic in-memory transport for tests.
///
/// Requests are recorded in [requests], then passed to the responder supplied
/// to the constructor.
final class MockTransport implements Transport {
  MockTransport(this._responder);

  final MockResponder _responder;

  /// Requests sent through this transport.
  final List<Request> requests = <Request>[];

  @override
  PlatformCapability get capability => PlatformCapability.test;

  @override
  Future<void> close() async {}

  @override
  Future<Response> send(Request request, Context context) async {
    requests.add(request);
    return _responder(request, context);
  }
}
