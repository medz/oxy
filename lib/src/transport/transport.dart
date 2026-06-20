import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import 'capability.dart';

/// Low-level transport used by `Client` after policies and middleware.
abstract interface class Transport {
  /// Capabilities exposed by this transport.
  PlatformCapability get capability;

  /// Sends a prepared [request].
  Future<Response> send(Request request, Context context);

  /// Releases transport resources.
  Future<void> close();
}
