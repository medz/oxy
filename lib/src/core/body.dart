import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;

import 'errors.dart';

enum BodyKind { empty, bytes, text, json, form, multipart, file, stream }

typedef BodyStreamFactory = Stream<List<int>> Function();

final class Body {
  static final Random _boundaryRandom = Random();
  static int _boundaryCounter = 0;

  Body._({
    required this.kind,
    required this.replayable,
    required BodyStreamFactory open,
    this.contentLength,
    this.contentType,
  }) : _open = open;

  final BodyKind kind;
  final bool replayable;
  final int? contentLength;
  final String? contentType;
  final BodyStreamFactory _open;
  bool _used = false;

  static Body empty() {
    return Body.fromBytes(const <int>[], kind: BodyKind.empty);
  }

  static Body fromBytes(List<int> bytes, {BodyKind kind = BodyKind.bytes}) {
    final data = Uint8List.fromList(bytes);
    return Body._(
      kind: kind,
      replayable: true,
      contentLength: data.length,
      open: () => Stream<List<int>>.value(data),
    );
  }

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
      ht.Body() => Body.fromHtBody(value),
      Stream<List<int>>() => Body.stream(value),
      _ => throw ArgumentError.value(value, 'value', 'Unsupported body input.'),
    };
  }

  static Body fromFormData(ht.FormData formData) {
    final encoded = formData.encodeMultipart(boundary: _multipartBoundary());
    return Body._(
      kind: BodyKind.multipart,
      replayable: true,
      contentLength: encoded.contentLength,
      contentType: encoded.contentType,
      open: () => encoded.stream,
    );
  }

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

  static Body fromBlob(ht.Blob blob) {
    return Body._(
      kind: blob is ht.File ? BodyKind.file : BodyKind.bytes,
      replayable: true,
      contentLength: blob.size,
      contentType: blob.type.isEmpty ? null : blob.type,
      open: () => blob.stream(),
    );
  }

  static Body fromHtBody(ht.Body body) {
    return Body._(
      kind: BodyKind.stream,
      replayable: true,
      open: () => body.clone(),
    );
  }

  static String _multipartBoundary() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final counter = (_boundaryCounter++).toRadixString(16);
    final random = _boundaryRandom.nextInt(0x3fffffff).toRadixString(16);
    return '----oxy-$timestamp-$counter-$random';
  }

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

  Future<String> text({Encoding encoding = utf8, int? maxBytes}) async {
    return encoding.decode(await bytes(maxBytes: maxBytes));
  }

  Future<Object?> json({int? maxBytes}) async {
    return jsonDecode(await text(maxBytes: maxBytes));
  }
}

final class ResponseBody {
  ResponseBody._({
    required bool replayable,
    required BodyStreamFactory open,
    this.contentLength,
  }) : _replayable = replayable,
       _open = open;

  final bool _replayable;
  final int? contentLength;
  final BodyStreamFactory _open;
  bool _used = false;

  bool get replayable => _replayable;

  static ResponseBody empty() {
    return ResponseBody.fromBytes(const <int>[]);
  }

  static ResponseBody fromBytes(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    return ResponseBody._(
      replayable: true,
      contentLength: data.length,
      open: () => Stream<List<int>>.value(data),
    );
  }

  static ResponseBody fromText(String value, {Encoding encoding = utf8}) {
    return ResponseBody.fromBytes(encoding.encode(value));
  }

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

  Future<String> text({Encoding encoding = utf8, int? maxBytes}) async {
    return encoding.decode(await bytes(maxBytes: maxBytes));
  }

  Future<Object?> json({int? maxBytes}) async {
    return jsonDecode(await text(maxBytes: maxBytes));
  }
}
