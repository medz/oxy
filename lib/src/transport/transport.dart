import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import 'capability.dart';

abstract interface class Transport {
  PlatformCapability get capability;

  Future<Response> send(Request request, Context context);
  Future<void> close();
}
