import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import 'capability.dart';
import 'transport.dart';

Transport createTransport({bool keepAlive = true}) => _UnsupportedTransport();

final class _UnsupportedTransport implements Transport {
  @override
  PlatformCapability get capability => const PlatformCapability(
    name: 'unsupported',
    uploadProgress: false,
    downloadProgress: false,
    streamingRequestBody: false,
    streamingResponseBody: false,
    proxyConfiguration: false,
    tlsConfiguration: false,
  );

  @override
  Future<void> close() async {}

  @override
  Future<Response> send(Request request, Context context) async {
    throw NetworkError(
      'No Oxy transport is available on this platform.',
      request: request,
    );
  }
}
