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
  external JSPromise<JSAny?> cancel([JSAny? reason]);
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
}) {
  late final StreamController<Uint8List> controller;
  late final ReadableStreamDefaultReader reader;
  late final Future<void> pumping;
  Future<void>? cancellation;
  Completer<void>? resume;
  var cancelled = false;
  var transferred = 0;
  var done = false;

  Future<void> cancelReader() {
    return cancellation ??= () async {
      if (done) return;
      try {
        await reader.cancel('cancelled'.toJS).toDart;
      } catch (_) {
        // A failed or already-aborted Fetch stream needs no second error.
      }
    }();
  }

  Future<void> pump() async {
    try {
      while (!cancelled) {
        if (controller.isPaused) {
          await resume!.future;
          if (cancelled) break;
        }
        final result = await reader.read().toDart;
        if (cancelled) break;
        if (result.done) {
          done = true;
          break;
        }
        final value = result.value;
        if (value == null) continue;
        final bytes = value.toDart;
        transferred += bytes.length;
        onProgress?.call(
          TransferProgress(transferred: transferred, total: total),
        );
        controller.add(bytes);
      }
    } catch (error, trace) {
      if (!cancelled) {
        var normalized = error;
        if (signal?.aborted == true) {
          normalized = signal?.reason is TimeoutError
              ? signal!.reason!
              : CancelError(
                  reason: signal?.reason,
                  request: request,
                  trace: trace,
                );
        } else if (error is! RequestError) {
          normalized = NetworkError(
            error.toString(),
            request: request,
            cause: error,
            trace: trace,
            sent: true,
          );
        }
        controller.addError(normalized, trace);
      }
    } finally {
      await cancelReader();
      reader.releaseLock();
      unawaited(controller.close());
    }
  }

  controller = StreamController<Uint8List>(
    onListen: () {
      reader = stream.getReader();
      pumping = pump();
    },
    onPause: () => resume = Completer<void>(),
    onResume: () {
      resume?.complete();
      resume = null;
    },
    onCancel: () async {
      cancelled = true;
      resume?.complete();
      await cancelReader();
      await pumping;
    },
  );
  return controller.stream;
}
