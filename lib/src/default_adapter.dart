import 'adapter.dart';
import 'adapter_request.dart';
import 'response.dart';

import '_internal/fetch.stub.dart'
    if (dart.library.io) '_internal/fetch.native.dart'
    if (dart.library.js_interop) '_internal/fetch.web.dart'
    as internal
    show fetch;

class DefaultAdapter implements Adapter {
  const DefaultAdapter();

  @override
  bool get isSupportWeb => true;

  @override
  Future<Response> fetch(Uri url, AdapterRequest request) =>
      internal.fetch(url, request);
}
