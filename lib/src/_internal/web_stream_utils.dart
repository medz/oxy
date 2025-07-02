import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

extension type UnderlyingSource._(JSObject _) implements JSObject {
  /// The type must set to `bytes`
  external factory UnderlyingSource({
    JSFunction? start,
    JSFunction? cancel,
    String? type,
  });
}

extension type ReadableStreamDefaultReaderResult._(JSObject _)
    implements JSObject {
  external bool done;
  external JSUint8Array? get value;
}

@JS("ReadableStreamDefaultReader")
extension type ReadableStreamDefaultReader._(JSObject _) {
  external void releaseLock();
  external JSPromise<ReadableStreamDefaultReaderResult> read();
}

@JS("ReadableStream")
extension type ReadableStream._(JSObject _) implements JSObject {
  external factory ReadableStream(UnderlyingSource _);
  external ReadableStreamDefaultReader getReader();
}

@JS("ReadableByteStreamController")
extension type ReadableByteStreamController._(JSObject _) {
  external void enqueue(JSUint8Array _);
  external void error(JSAny? _);
  external void close();
}

ReadableStream toWebReadableStream(Stream<Uint8List> stream) {
  late final StreamSubscription<Uint8List> subscription;

  void start(ReadableByteStreamController controller) async {
    void error(e) => controller.error(e?.toString().toJS);
    void done() {
      try {
        controller.close();
      } catch (_) {}
    }

    subscription = stream.listen(
      (event) {
        if (event.isNotEmpty) controller.enqueue(event.toJS);
      },
      onError: error,
      onDone: done,
    );
  }

  void cancel() => unawaited(subscription.cancel());

  final source = UnderlyingSource(
    type: "bytes",
    start: start.toJS,
    cancel: cancel.toJS,
  );

  return ReadableStream(source);
}

Stream<Uint8List> toDartStream(ReadableStream stream) async* {
  final reader = stream.getReader();
  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) break;
      if (result.value == null) continue;
      yield result.value!.toDart;
    }
  } finally {
    reader.releaseLock();
  }
}
