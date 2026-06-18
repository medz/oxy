import 'transport.dart';
import 'transport.stub.dart'
    if (dart.library.io) 'transport.native.dart'
    if (dart.library.js_interop) 'transport.web.dart'
    as platform;

Transport createDefaultTransport({bool keepAlive = true}) {
  return platform.createTransport(keepAlive: keepAlive);
}
