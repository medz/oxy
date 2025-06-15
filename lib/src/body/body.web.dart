import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../url_search_params/url_search_params.dart' show URLSearchParams;

// TODO: to FromData
extension type Body._(JSAny _) implements JSAny {
  factory Body.string(String value) => Body._(value.toJS);
  factory Body.urlSearchParams(URLSearchParams params) =>
      Body._(params as dynamic);
  factory Body.buffer(ByteBuffer buffer) => Body._(buffer.toJS);
  factory Body.bytes(TypedData bytes) => Body._(bytes.buffer.toJS);
  factory Body.stream(Stream<Uint8List> stream) => Body._(stream.toJS);

  external bool get bodyUsed;

  @JS("body")
  external _ReadableStream<JSUint8Array>? get _body;
  Stream<Uint8List>? get body => _body?.toDart;

  @JS("text")
  external JSPromise<JSString> _text();
  Future<String> text() async {
    final str = await _text().toDart;
    return str.toDart;
  }

  @JS("json")
  external JSPromise<JSAny?> _json();
  Future<Object?> json() async {
    final obj = await _json().toDart;
    return obj.toDartJson;
  }

  @JS("bytes")
  external JSPromise<JSUint8Array> _bytes();
  Future<Uint8List> bytes() async {
    final bytes = await _bytes().toDart;
    return bytes.toDart;
  }

  @JS("arrayBuffer")
  external JSPromise<JSArrayBuffer> _arrayBuffer();
  Future<ByteBuffer> buffer() async {
    final buffer = await _arrayBuffer().toDart;
    return buffer.toDart;
  }
}

extension type _ReadableStreamReadValueResult<T extends JSAny>._(JSObject _)
    implements JSObject {
  external bool done;
  external T? value;
}

@JS("ReadableStreamDefaultReader")
extension type _ReadableStreamDefaultReader<T extends JSAny>._(JSObject _) {
  external void releaseLock();
  external JSPromise<_ReadableStreamReadValueResult<T>> read();
}

@JS("ReadableStream")
extension type _ReadableStream<T extends JSAny>._(JSObject _)
    implements JSObject {
  external _ReadableStreamDefaultReader<T> getReader();
}

extension on _ReadableStream<JSUint8Array> {
  Stream<Uint8List> get toDart async* {
    final reader = getReader();
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
}

@JS("ReadableStreamDefaultController")
extension type _ReadableStreamDefaultController<T extends JSAny>._(JSObject _)
    implements JSObject {
  external void close();
  external void enqueue(T chunk);
  external void error(JSAny? e);
}

extension on Stream<Uint8List> {
  _ReadableStream<JSUint8Array> get toJS {
    late final StreamSubscription<Uint8List> subscription;

    void start(_ReadableStreamDefaultController<JSUint8Array> controller) {
      subscription = listen(
        (chunk) => controller.enqueue(chunk.toJS),
        onError: (e) => controller.error(e.jsify()),
        onDone: () => controller.close(),
      );
    }

    void cancel() => unawaited(subscription.cancel());

    final underlyingSource = JSObject()
      ..setProperty('type'.toJS, 'bytes'.toJS)
      ..setProperty("start".toJS, start.toJS)
      ..setProperty("cancel".toJS, cancel.toJS);

    return _ReadableStream._(underlyingSource);
  }
}

@JS("Object")
extension type _JSObject._(JSObject _) {
  external static JSArray<JSString> keys(JSObject _);
}

extension on JSObject {
  Map get toDartMap {
    final keys = _JSObject.keys(this);
    final result = {};
    for (final key in keys.toDart) {
      if (hasProperty(key).toDart) {
        result[key.toDart] = getProperty(key).toDartJson;
      }
    }

    return result;
  }
}

extension on JSAny? {
  Object? get toDartJson {
    if (this == null) return null;
    return switch (this) {
      String() || num() || bool() => this,
      JSSymbol symbol => Symbol(symbol.toString()),
      JSArray arr => arr.toDart.map((e) => e.toDartJson),
      JSObject obj => obj.toDartMap,
      _ => dartify(),
    };
  }
}
