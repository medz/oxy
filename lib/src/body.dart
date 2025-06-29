import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '_internal/mark_stream.dart';
import '_internal/tee_stream_to_two_streams.dart';

/// [Request]/[Response] common body properties base class.
class Body extends Stream<Uint8List> {
  /// Creates a new body from a stream.
  Body(Stream<Uint8List> source) : _source = MarkStream(source);

  MarkStream<Uint8List> _source;

  @override
  bool get isBroadcast => _source.isBroadcast;

  /// Indicates whether the body has been used.
  bool get bodyUsed => _source.used;

  Stream<Uint8List> get body => this;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Clone a new body without affecting the original body.
  Body clone() {
    final (a, b) = teeStreamToTwoStreams(_source);
    _source = MarkStream(a);
    return Body(b);
  }

  /// Returns the body as a [Uint8List].
  Future<Uint8List> bytes() async {
    return fold(Uint8List(0), (bytes, chunk) {
      final newBytes = Uint8List(bytes.length + chunk.length);
      newBytes.setRange(0, bytes.length, bytes);
      newBytes.setRange(bytes.length, newBytes.length, chunk);
      return newBytes;
    });
  }

  /// Returns the body as a [String].
  Future<String> text() => utf8.decodeStream(this);

  /// Returns the body as JSON parsed data.
  Future json() async => jsonDecode(await text());
}
