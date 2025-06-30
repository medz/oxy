import 'dart:js_interop';
import 'dart:typed_data';

import '../web_stream_utils.dart';

extension type Body._(JSObject _) implements JSObject {
  factory Body(Stream<Uint8List> source) => Body._(toWebReadableStream(source));
  // Private API, impls internal request/response
  external bool get bodyUsed;
  external Stream<Uint8List> get body;
}
