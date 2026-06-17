import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../core/abort.dart';
import '../core/errors.dart';
import '../core/request.dart';
import '../options.dart';

extension type UnderlyingSource._(JSObject _) implements JSObject {
  external factory UnderlyingSource({
    JSFunction? start,
    JSFunction? cancel,
    String? type,
  });
}

extension type ReadableStreamDefaultReaderResult._(JSObject _)
    implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

@JS('ReadableStreamDefaultReader')
extension type ReadableStreamDefaultReader._(JSObject _) {
  external void releaseLock();
  external JSPromise<ReadableStreamDefaultReaderResult> read();
}

@JS('ReadableStream')
extension type ReadableStream._(JSObject _) implements JSObject {
  external factory ReadableStream(UnderlyingSource source);
  external ReadableStreamDefaultReader getReader();
}

@JS('ReadableByteStreamController')
extension type ReadableByteStreamController._(JSObject _) {
  external void enqueue(JSUint8Array value);
  external void error(JSAny? error);
  external void close();
}

ReadableStream toWebReadableStream(Stream<Uint8List> stream) {
  late final StreamSubscription<Uint8List> subscription;

  void start(ReadableByteStreamController controller) {
    subscription = stream.listen(
      (event) {
        if (event.isNotEmpty) {
          controller.enqueue(event.toJS);
        }
      },
      onError: (Object error) {
        controller.error(error.toString().toJS);
      },
      onDone: () {
        try {
          controller.close();
        } catch (_) {}
      },
    );
  }

  void cancel() {
    unawaited(subscription.cancel());
  }

  return ReadableStream(
    UnderlyingSource(type: 'bytes', start: start.toJS, cancel: cancel.toJS),
  );
}

Stream<Uint8List> toDartStream(
  ReadableStream stream, {
  required Request request,
  AbortSignal? signal,
  ProgressCallback? onProgress,
  int? total,
}) async* {
  final reader = stream.getReader();
  var transferred = 0;

  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) {
        break;
      }
      final value = result.value;
      if (value == null) {
        continue;
      }
      final bytes = value.toDart;
      transferred += bytes.length;
      onProgress?.call(
        TransferProgress(transferred: transferred, total: total),
      );
      yield bytes;
    }
  } catch (error, trace) {
    if (signal?.aborted == true) {
      throw CancelError(reason: signal?.reason, request: request, trace: trace);
    }
    if (error is RequestError) {
      rethrow;
    }
    throw NetworkError(
      error.toString(),
      request: request,
      cause: error,
      trace: trace,
      sent: true,
    );
  } finally {
    reader.releaseLock();
  }
}
