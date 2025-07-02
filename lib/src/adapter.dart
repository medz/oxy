import 'adapter_request.dart';
import 'response.dart';

abstract interface class Adapter {
  const Adapter();

  bool get isSupportWeb;
  Future<Response> fetch(Uri url, AdapterRequest request);
}
