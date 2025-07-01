import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '_internal/tee_stream_to_two_streams.dart';
import 'data_helpers.dart';

base class FormDataEntry {
  factory FormDataEntry.text(String text) = FormDataTextEntry;
  factory FormDataEntry.file(
    Stream<List<int>> stream, {
    String? filename,
    String? contentType,
    int? size,
  }) = FormDataFileEntry;
}

final class FormDataTextEntry implements FormDataEntry {
  const FormDataTextEntry(this.text);

  final String text;
}

final class FormDataFileEntry extends Stream<Uint8List>
    implements FormDataEntry, DataHelpers {
  FormDataFileEntry(
    Stream<List<int>> stream, {
    String? filename,
    String? contentType,
    int? size,
  }) : _filename = filename ?? 'file',
       _contentType = contentType ?? 'application/octet-stream',
       _size = size,
       _stream = stream;

  final String _filename;
  final String _contentType;

  int? _size;
  Future<int>? _sizeFuture;

  Stream<List<int>> _stream;
  Stream<Uint8List> get _optimizedStream {
    if (_stream is Stream<Uint8List>) {
      return _stream as Stream<Uint8List>;
    }

    return _stream.map((chunk) {
      if (chunk is Uint8List) return chunk;
      return Uint8List.fromList(chunk);
    });
  }

  String get filename => _filename;
  String get contentType => _contentType;

  @override
  bool get isBroadcast => _stream.isBroadcast;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_size != null || _sizeFuture != null) {
      return _optimizedStream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
    final controller = StreamController<Uint8List>();
    final completer = Completer<int>();

    controller.onListen = () {
      int size = 0;
      final subscription = _optimizedStream.listen((event) {
        controller.add(event);
        size += event.lengthInBytes;
      });
      subscription.onError((e, s) {
        controller.addError(e, s);
        if (!completer.isCompleted) {
          completer.completeError(e, s);
        }
      });
      subscription.onDone(() {
        _size = size;
        controller.close();
        if (!completer.isCompleted) {
          completer.complete(size);
        }
      });
    };
    _sizeFuture = completer.future;

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<int> size() {
    if (_size != null || _sizeFuture != null) {
      return Future.value(_size ?? _sizeFuture);
    }

    final (a, b) = teeStreamToTwoStreams(this);
    _stream = b;

    return _sizeFuture = a
        .fold<int>(0, (size, chunk) => size + chunk.lengthInBytes)
        .then((size) => _size = size);
  }

  @override
  Future<Uint8List> bytes() {
    return fold(Uint8List(0), (bytes, chunk) {
      final newBytes = Uint8List(bytes.length + chunk.length);
      newBytes.setRange(0, bytes.length, bytes);
      newBytes.setRange(bytes.length, newBytes.length, chunk);
      return newBytes;
    });
  }

  @override
  Future<Object?> json() async {
    return jsonDecode(await text());
  }

  @override
  Future<String> text() => utf8.decodeStream(this);
}

class FormData {}
