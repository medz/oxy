import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../mark_stream.dart';
import '../tee_stream_to_two_streams.dart';

/// [Request]/[Response] common body properties base class.
class Body {
  /// Creates a new body from a stream.
  Body(Stream<Uint8List> source) : _source = MarkStream(source);

  MarkStream<Uint8List> _source;

  /// Indicates whether the body has been used.
  bool get bodyUsed => _source.used;

  Stream<Uint8List> get body => _source;

  /// Clone a new body without affecting the original body.
  Body clone() {
    final (a, b) = teeStreamToTwoStreams(_source);
    _source = MarkStream(a);
    return Body(b);
  }

  /// Returns the body as a [Uint8List].
  Future<Uint8List> bytes() async {
    return body.fold(Uint8List(0), (bytes, chunk) {
      final newBytes = Uint8List(bytes.length + chunk.length);
      newBytes.setRange(0, bytes.length, bytes);
      newBytes.setRange(bytes.length, newBytes.length, chunk);
      return newBytes;
    });
  }

  /// Returns the body as a [String].
  Future<String> text() => utf8.decodeStream(body);

  /// Returns the body as JSON parsed data.
  Future json() async => jsonDecode(await text());
}
