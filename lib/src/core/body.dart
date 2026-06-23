import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;

import 'errors.dart';

/// Opens a fresh byte stream for a replayable body.
typedef _BodyStreamFactory = Stream<List<int>> Function();

/// A request body backed by `ht.Body`.
///
/// Oxy uses [replayable] to decide whether a request can be retried safely.
/// Bodies created from raw `Stream<List<int>>` values are one-shot; pass an
/// `ht.Body(stream)` when tee-based clone semantics are desired.
final class Body extends ht.Body {
  /// Creates a request body from any `ht.BodyInit` value.
  Body([super.init])
    : replayable = _defaultReplayable(init),
      _streamUpload = _defaultStreamUpload(init),
      super();

  Body._withPolicy(
    super.init, {
    required this.replayable,
    required bool streamUpload,
  }) : _streamUpload = streamUpload,
       super();

  /// Whether [clone] can create an independent body for another attempt.
  final bool replayable;

  final bool _streamUpload;

  @override
  Body clone() {
    if (!replayable) {
      throw const BodyStateError('Body is not replayable.');
    }
    return Body._withPolicy(
      super.clone(),
      replayable: true,
      streamUpload: _streamUpload,
    );
  }

  static bool _defaultReplayable(Object? init) {
    return switch (init) {
      Body() => init.replayable,
      ht.Body() => true,
      Stream<List<int>>() => false,
      _ => true,
    };
  }

  static bool _defaultStreamUpload(Object? init) {
    return switch (init) {
      Body() => init._streamUpload,
      ht.Body() => true,
      Stream<List<int>>() || ht.FormData() || ht.Blob() => true,
      _ => false,
    };
  }
}

/// Converts request body inputs to an Oxy [Body].
Body? requestBodyFrom(Object? value) {
  return value == null
      ? null
      : value is Body
      ? value
      : Body(value);
}

/// Creates a JSON request body.
Body requestJsonBody(Object? value) {
  return Body(ht.Blob([jsonEncode(value)], 'application/json; charset=utf-8'));
}

/// Returns a body byte length when it is available without consuming [body].
int? knownBodyLength(ht.Body? body) {
  if (body == null) {
    return null;
  }
  try {
    return body.size;
  } on UnsupportedError {
    return null;
  }
}

/// Whether web transport should upload [body] as a stream.
bool streamsRequestBody(Body? body) {
  return body?._streamUpload ?? false;
}

/// A response body with replayability and content length metadata.
///
/// Response bodies from bytes and text are replayable. Response bodies from a
/// raw stream are one-shot unless middleware buffers them into a new
/// [ResponseBody].
final class ResponseBody {
  ResponseBody._({
    required bool replayable,
    required _BodyStreamFactory open,
    this.contentLength,
  }) : _replayable = replayable,
       _open = open;

  final bool _replayable;

  /// The known content length, or `null` when unknown.
  final int? contentLength;
  final _BodyStreamFactory _open;
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
