import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '_internal/mark_stream.dart';
import '_internal/tee_stream_to_two_streams.dart';
import '_internal/data_helpers.dart';
import 'formdata.dart';
import 'headers.dart';

/// A base class that represents the body of HTTP requests and responses.
///
/// This class provides a common interface for handling request/response bodies
/// as streams of bytes, with convenient methods for consuming the data in
/// different formats (bytes, text, JSON).
///
/// The body can only be consumed once unless cloned. Use [bodyUsed] to check
/// if the body has already been consumed, and [clone] to create a new instance
/// that can be consumed independently.
class Body extends FormDataHelper implements DataHelpers {
  /// Creates a new body from a stream of bytes.
  ///
  /// The [source] stream will be wrapped in a [MarkStream] to track usage
  /// and prevent multiple consumption of single-subscription streams.
  Body(Stream<Uint8List> source)
    : _source = MarkStream(source),
      headers = Headers({"Content-Type": "application/octet-stream"});

  /// Creates a Body from plain text content.
  ///
  /// The [text] will be UTF-8 encoded into a stream of bytes.
  ///
  /// Example:
  /// ```dart
  /// final body = Body.text('Hello, World!');
  /// final content = await body.text();
  /// ```
  factory Body.text(String text) {
    final bytes = utf8.encode(text);
    final bodyStream = Stream.value(bytes);
    return Body._(
      bodyStream,
      Headers({
        'Content-Type': 'text/plain; charset=utf-8',
        'Content-Length': bytes.lengthInBytes.toString(),
      }),
    );
  }

  /// Creates a Body from JSON data.
  ///
  /// The [data] will be serialized to JSON and then UTF-8 encoded into
  /// a stream of bytes.
  ///
  /// Example:
  /// ```dart
  /// final body = Body.json({'message': 'Hello', 'count': 42});
  /// final data = await body.json();
  /// ```
  factory Body.json(Object? data) {
    final text = jsonEncode(data);
    final bytes = utf8.encode(text);
    return Body._(
      Stream.value(bytes),
      Headers({
        'Content-Type': 'application/json',
        'Content-Length': bytes.lengthInBytes.toString(),
      }),
    );
  }

  /// Creates a Body from binary data.
  ///
  /// The [bytes] will be used directly as the body content.
  ///
  /// Example:
  /// ```dart
  /// final data = Uint8List.fromList([1, 2, 3, 4]);
  /// final body = Body.bytes(data);
  /// final content = await body.bytes();
  /// ```
  factory Body.bytes(Uint8List bytes) {
    final bodyStream = Stream.value(bytes);
    return Body._(
      bodyStream,
      Headers({
        'Content-Type': 'application/octet-stream',
        'Content-Length': bytes.lengthInBytes.toString(),
      }),
    );
  }

  /// Creates a Body from FormData.
  ///
  /// The [formData] will be converted to its multipart stream representation.
  ///
  /// Example:
  /// ```dart
  /// final formData = FormData();
  /// formData.append('name', FormDataEntry.text('John'));
  /// final body = Body.formData(formData);
  /// ```
  factory Body.formData(FormData formData) {
    return Body._(
      formData.stream(),
      Headers({
        'Content-Type': 'multipart/form-data; boundary=${formData.boundary}',
      }),
    );
  }

  /// Internal constructor with headers.
  Body._(Stream<Uint8List> source, this.headers) : _source = MarkStream(source);

  /// Creates an empty body without any default headers.
  ///
  /// This is useful when you need an empty body that doesn't automatically
  /// add Content-Type headers.
  factory Body.empty() {
    return Body._(Stream.empty(), Headers());
  }

  MarkStream<Uint8List> _source;

  /// The headers associated with this body.
  ///
  /// Contains Content-Type and other headers that describe the body content.
  /// These headers are automatically set by the factory methods.
  ///
  /// Example:
  /// ```dart
  /// final body = Body.json({'key': 'value'});
  /// print(body.headers.get('Content-Type')); // 'application/json'
  /// ```
  @override
  final Headers headers;

  /// Indicates whether the body has been consumed.
  ///
  /// Returns `true` if any of the consumption methods ([bytes], [text], [json])
  /// or the [body] stream has been listened to. Once a body is used, it cannot
  /// be consumed again unless it's a broadcast stream.
  ///
  /// Use [clone] to create a new consumable copy of the body.
  bool get bodyUsed => _source.used;

  /// The underlying stream of bytes that represents the body content.
  ///
  /// This stream can only be listened to once (unless it's a broadcast stream).
  /// Accessing this stream will mark the body as used. Use [clone] if you need
  /// to access the body multiple times.
  ///
  /// Example:
  /// ```dart
  /// await for (final chunk in body.body) {
  ///   // Process each chunk of bytes
  ///   print('Received ${chunk.length} bytes');
  /// }
  /// ```
  @override
  Stream<Uint8List> get body => _source;

  /// Creates a clone of this body that can be consumed independently.
  ///
  /// This method splits the underlying stream into two identical streams,
  /// allowing both the original body and the cloned body to be consumed
  /// separately. Neither body will be marked as used until their respective
  /// streams are actually consumed.
  ///
  /// Example:
  /// ```dart
  /// final originalBody = Body(dataStream);
  /// final clonedBody = originalBody.clone();
  ///
  /// // Both can now be consumed independently
  /// final text1 = await originalBody.text();
  /// final text2 = await clonedBody.text();
  /// ```
  ///
  /// Returns a new [Body] instance with an identical data stream.
  Body clone() {
    final (a, b) = teeStreamToTwoStreams(_source);
    _source = MarkStream(a);
    // Clone headers to avoid shared state
    final clonedHeaders = Headers(
      headers.entries().fold<Map<String, String>>({}, (map, entry) {
        map[entry.$1] = entry.$2;
        return map;
      }),
    );
    return Body._(b, clonedHeaders);
  }

  @override
  Future<Uint8List> bytes() async {
    return body.fold(Uint8List(0), (bytes, chunk) {
      final newBytes = Uint8List(bytes.length + chunk.length);
      newBytes.setRange(0, bytes.length, bytes);
      newBytes.setRange(bytes.length, newBytes.length, chunk);
      return newBytes;
    });
  }

  @override
  Future<String> text() => utf8.decodeStream(body);

  @override
  Future json() async => jsonDecode(await text());
}
