import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;

import 'errors.dart';

/// The source kind of a request body.
enum BodyKind { empty, bytes, text, json, form, multipart, file, stream }

/// Opens a fresh byte stream for a replayable body.
typedef BodyStreamFactory = Stream<List<int>> Function();

/// A request body with replayability and metadata.
///
/// Oxy uses [replayable] to decide whether a request can be retried safely.
/// Bodies created from bytes, text, JSON, forms, URL search params, blobs, and
/// replayable stream factories are replayable. Bodies created from a raw
/// `Stream<List<int>>` are one-shot.
final class Body {
  Body._({
    required this.kind,
    required this.replayable,
    required BodyStreamFactory open,
    this.contentLength,
    this.contentType,
  }) : _open = open;

  /// The original body source kind.
  final BodyKind kind;

  /// Whether [open] can be called more than once.
  final bool replayable;

  /// The known content length, or `null` when unknown.
  final int? contentLength;

  /// The content type supplied by the body source, or `null`.
  final String? contentType;
  final BodyStreamFactory _open;
  bool _used = false;

  /// Creates an empty replayable body.
  static Body empty() {
    return Body.fromBytes(const <int>[], kind: BodyKind.empty);
  }

  /// Creates a replayable body from [bytes].
  static Body fromBytes(List<int> bytes, {BodyKind kind = BodyKind.bytes}) {
    final data = Uint8List.fromList(bytes);
    return Body._(
      kind: kind,
      replayable: true,
      contentLength: data.length,
      open: () => Stream<List<int>>.value(Uint8List.fromList(data)),
    );
  }

  /// Creates a replayable text body.
  static Body fromText(
    String value, {
    Encoding encoding = utf8,
    String contentType = 'text/plain; charset=utf-8',
  }) {
    final data = encoding.encode(value);
    return Body._(
      kind: BodyKind.text,
      replayable: true,
      contentLength: data.length,
      contentType: contentType,
      open: () => Stream<List<int>>.value(Uint8List.fromList(data)),
    );
  }

  /// Creates a replayable JSON body.
  static Body fromJson(
    Object? value, {
    String contentType = 'application/json; charset=utf-8',
  }) {
    final data = utf8.encode(jsonEncode(value));
    return Body._(
      kind: BodyKind.json,
      replayable: true,
      contentLength: data.length,
      contentType: contentType,
      open: () => Stream<List<int>>.value(Uint8List.fromList(data)),
    );
  }

  /// Creates a one-shot streaming body.
  static Body stream(Stream<List<int>> stream, {int? contentLength}) {
    var consumed = false;
    return Body._(
      kind: BodyKind.stream,
      replayable: false,
      contentLength: contentLength,
      open: () {
        if (consumed) {
          throw const BodyStateError('Request body stream was already used.');
        }
        consumed = true;
        return stream;
      },
    );
  }

  /// Creates a replayable streaming body from an [open] factory.
  static Body replayableStream(
    BodyStreamFactory open, {
    int? contentLength,
    BodyKind kind = BodyKind.stream,
    String? contentType,
  }) {
    return Body._(
      kind: kind,
      replayable: true,
      contentLength: contentLength,
      contentType: contentType,
      open: open,
    );
  }

  /// Converts common request body inputs to a [Body].
  ///
  /// Returns `null` for `null`. Throws [ArgumentError] for unsupported inputs.
  static Body? from(Object? value) {
    return switch (value) {
      null => null,
      Body() => value,
      String() => Body.fromText(value),
      Uint8List() => Body.fromBytes(value),
      List<int>() => Body.fromBytes(value),
      ht.FormData() => Body.fromFormData(value),
      ht.URLSearchParams() => Body.fromUrlSearchParams(value),
      ht.Blob() => Body.fromBlob(value),
      Stream<List<int>>() => Body.stream(value),
      _ => throw ArgumentError.value(value, 'value', 'Unsupported body input.'),
    };
  }

  /// Creates a replayable multipart form body.
  static Body fromFormData(ht.FormData formData) {
    final encoded = formData.encodeMultipart();
    return Body._(
      kind: BodyKind.multipart,
      replayable: true,
      contentLength: encoded.contentLength,
      contentType: encoded.contentType,
      open: () => encoded.stream,
    );
  }

  /// Creates a replayable `application/x-www-form-urlencoded` body.
  static Body fromUrlSearchParams(ht.URLSearchParams params) {
    final data = utf8.encode(params.toString());
    return Body._(
      kind: BodyKind.form,
      replayable: true,
      contentLength: data.length,
      contentType: 'application/x-www-form-urlencoded; charset=utf-8',
      open: () => Stream<List<int>>.value(Uint8List.fromList(data)),
    );
  }

  /// Creates a replayable body from a [ht.Blob].
  static Body fromBlob(ht.Blob blob) {
    return Body._(
      kind: BodyKind.file,
      replayable: true,
      contentLength: blob.size,
      contentType: blob.type.isEmpty ? null : blob.type,
      open: () => blob.stream(),
    );
  }

  /// Opens the body stream.
  ///
  /// Throws [BodyStateError] if this body is not replayable and was already
  /// opened.
  Stream<Uint8List> open() {
    if (!replayable) {
      if (_used) {
        throw const BodyStateError('Body is not replayable.');
      }
      _used = true;
    }

    return _open().map((chunk) {
      return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    });
  }

  /// Reads the body as bytes.
  ///
  /// Throws [BodyTooLargeError] if [maxBytes] is set and the body exceeds it.
  Future<Uint8List> bytes({int? maxBytes}) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in open()) {
      builder.add(chunk);
      if (maxBytes != null && builder.length > maxBytes) {
        throw BodyTooLargeError(limit: maxBytes);
      }
    }
    return builder.takeBytes();
  }

  /// Reads the body as text using [encoding].
  Future<String> text({Encoding encoding = utf8, int? maxBytes}) async {
    return encoding.decode(await bytes(maxBytes: maxBytes));
  }

  /// Reads and decodes the body as JSON.
  Future<Object?> json({int? maxBytes}) async {
    return jsonDecode(await text(maxBytes: maxBytes));
  }
}

/// A response body with replayability and content length metadata.
///
/// Response bodies from bytes and text are replayable. Response bodies from a
/// raw stream are one-shot unless middleware buffers them into a new
/// [ResponseBody].
final class ResponseBody {
  ResponseBody._({
    required bool replayable,
    required BodyStreamFactory open,
    this.contentLength,
  }) : _replayable = replayable,
       _open = open;

  final bool _replayable;

  /// The known content length, or `null` when unknown.
  final int? contentLength;
  final BodyStreamFactory _open;
  bool _used = false;

  /// Whether [open] can be called more than once.
  bool get replayable => _replayable;

  /// Creates an empty replayable response body.
  static ResponseBody empty() {
    return ResponseBody.fromBytes(const <int>[]);
  }

  /// Creates a replayable response body from [bytes].
  static ResponseBody fromBytes(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    return ResponseBody._(
      replayable: true,
      contentLength: data.length,
      open: () => Stream<List<int>>.value(Uint8List.fromList(data)),
    );
  }

  /// Creates a replayable text response body.
  static ResponseBody fromText(String value, {Encoding encoding = utf8}) {
    return ResponseBody.fromBytes(encoding.encode(value));
  }

  /// Creates a one-shot streaming response body.
  static ResponseBody stream(Stream<List<int>> stream, {int? contentLength}) {
    var consumed = false;
    return ResponseBody._(
      replayable: false,
      contentLength: contentLength,
      open: () {
        if (consumed) {
          throw const BodyStateError('Response body stream was already used.');
        }
        consumed = true;
        return stream;
      },
    );
  }

  /// Opens the response body stream.
  ///
  /// Throws [BodyStateError] if this body is not replayable and was already
  /// opened.
  Stream<Uint8List> open() {
    if (!_replayable) {
      if (_used) {
        throw const BodyStateError('Response body is not replayable.');
      }
      _used = true;
    }

    return _open().map((chunk) {
      return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    });
  }

  /// Reads the response body as bytes.
  ///
  /// Throws [BodyTooLargeError] if [maxBytes] is set and the body exceeds it.
  Future<Uint8List> bytes({int? maxBytes}) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in open()) {
      builder.add(chunk);
      if (maxBytes != null && builder.length > maxBytes) {
        throw BodyTooLargeError(limit: maxBytes);
      }
    }
    return builder.takeBytes();
  }

  /// Reads the response body as text using [encoding].
  Future<String> text({Encoding encoding = utf8, int? maxBytes}) async {
    return encoding.decode(await bytes(maxBytes: maxBytes));
  }

  /// Reads and decodes the response body as JSON.
  Future<Object?> json({int? maxBytes}) async {
    return jsonDecode(await text(maxBytes: maxBytes));
  }
}
