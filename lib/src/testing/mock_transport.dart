import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../transport/capability.dart';
import '../transport/transport.dart';

typedef MockResponder =
    Future<Response> Function(Request request, Context context);

final class MockTransport implements Transport {
  MockTransport(this._responder);

  final MockResponder _responder;
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
