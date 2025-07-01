import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mime/mime.dart';

import '_internal/entry_store.dart';
import '_internal/tee_stream_to_two_streams.dart';
import 'data_helpers.dart';

/// Abstract base class for form data entries that can be included in a [FormData].
///
/// A form data entry represents a single field in a multipart form, which can
/// be either text content or file content. All entries are streams of bytes
/// that can be consumed as part of the form data serialization process.
abstract base class FormDataEntry implements Stream<Uint8List> {
  /// Creates a text entry with the given [text] content.
  ///
  /// The text will be UTF-8 encoded when the entry is consumed as a stream.
  factory FormDataEntry.text(String text) = FormDataTextEntry;

  /// Creates a file entry from a [stream] of bytes.
  ///
  /// Optional parameters:
  /// - [filename]: The name of the file (defaults to 'file')
  /// - [contentType]: The MIME type of the file (defaults to 'application/octet-stream')
  /// - [size]: The size of the file in bytes (will be calculated if not provided)
  factory FormDataEntry.file(
    Stream<List<int>> stream, {
    String? filename,
    String? contentType,
    int? size,
  }) = FormDataFileEntry;
}

/// A form data entry that contains text content.
///
/// This entry type is used for regular form fields that contain string values.
/// The text is UTF-8 encoded when consumed as a byte stream.
final class FormDataTextEntry extends Stream<Uint8List>
    implements FormDataEntry {
  /// Creates a text entry with the given [text] content.
  FormDataTextEntry(this.text);

  /// The text content of this entry.
  final String text;

  late final Stream<Uint8List> _stream = Stream.value(utf8.encode(text));

  @override
  bool get isBroadcast => _stream.isBroadcast;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// A form data entry that contains file content.
///
/// This entry type is used for file uploads in multipart forms. It provides
/// access to the file's content as a stream of bytes, along with metadata
/// such as filename and content type.
final class FormDataFileEntry extends Stream<Uint8List>
    implements FormDataEntry, DataHelpers {
  /// Creates a file entry from a [stream] of bytes.
  ///
  /// Parameters:
  /// - [stream]: The source stream containing the file data
  /// - [filename]: The name of the file (defaults to 'file')
  /// - [contentType]: The MIME type (defaults to 'application/octet-stream')
  /// - [size]: The file size in bytes (calculated automatically if not provided)
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

  /// The filename of this file entry.
  String get filename => _filename;

  /// The MIME content type of this file entry.
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

  /// Returns the size of the file in bytes.
  ///
  /// If the size was provided during construction, returns it immediately.
  /// Otherwise, calculates the size by consuming the stream. The result is
  /// cached for subsequent calls.
  ///
  /// Note: If the size needs to be calculated, this method will split the
  /// underlying stream to preserve the original data for later consumption.
  Future<int> size() {
    if (_size != null) return Future.value(_size!);
    if (_sizeFuture != null) return _sizeFuture!;

    final (sizeStream, dataStream) = teeStreamToTwoStreams(_optimizedStream);
    _stream = dataStream;

    return _sizeFuture = sizeStream
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

/// A container for multipart form data that can be used in HTTP requests.
///
/// FormData provides a way to construct multipart/form-data content, which is
/// commonly used for HTML forms that include file uploads. Each field in the
/// form is represented by a [FormDataEntry] that can contain either text or
/// file content.
///
/// Example:
/// ```dart
/// final formData = FormData();
/// formData.append('username', FormDataEntry.text('john_doe'));
/// formData.append('avatar', FormDataEntry.file(
///   File('avatar.jpg').openRead(),
///   filename: 'avatar.jpg',
///   contentType: 'image/jpeg',
/// ));
///
/// // Use in HTTP request
/// final stream = formData.stream();
/// ```
class FormData extends EntryStore<FormDataEntry> {
  /// Generates a random boundary string for multipart content.
  ///
  /// The boundary is used to separate different parts in the multipart data.
  /// It starts with 'OxyBoundary' followed by 32 random alphanumeric characters
  /// to ensure uniqueness.
  static String generateBoundary() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return 'OxyBoundary${List.generate(32, (_) => chars[random.nextInt(chars.length)]).join()}';
  }

  static Map<String, String> _getHeaderParams(String? header) {
    final result = <String, String>{};
    if (header == null || header.isEmpty) return result;

    for (final part in header.split(';')) {
      final [name, ...values] = part.split('=');
      final normalizedName = name.toLowerCase().trim();
      if (normalizedName.isEmpty) continue;

      String value = values.join('=').trim();
      if (value.startsWith("'") || value.startsWith('"')) {
        value = value.substring(1);
      }
      if (value.endsWith("'") || value.endsWith('"')) {
        value = value.substring(0, value.length - 1);
      }

      result[normalizedName] = value;
    }

    return result;
  }

  /// Parses multipart form data from a stream.
  ///
  /// Takes a [boundary] string and a [stream] of bytes containing multipart
  /// data, and returns a [FormData] instance with all the parsed entries.
  ///
  /// Text fields are decoded as UTF-8 strings, while file fields preserve
  /// their original content type and filename from the multipart headers.
  ///
  /// Example:
  /// ```dart
  /// final formData = await FormData.parse(
  ///   'boundary123',
  ///   requestBodyStream,
  /// );
  /// ```
  static Future<FormData> parse(
    String boundary,
    Stream<Uint8List> stream,
  ) async {
    final form = FormData._(boundary);
    final transformer = MimeMultipartTransformer(boundary).bind(stream);

    await for (final part in transformer) {
      final disposition = part.headers['content-disposition'];
      final params = _getHeaderParams(disposition);
      final name = params['name'];
      if (name == null) continue;

      final filename = params['filename'];
      if (filename == null) {
        form.append(name, FormDataTextEntry(await utf8.decodeStream(part)));
        continue;
      }

      final contentType = part.headers['content-type']
          ?.split(';')
          .firstOrNull
          ?.trim();
      form.append(
        name,
        FormDataFileEntry(part, filename: filename, contentType: contentType),
      );
    }

    return form;
  }

  FormData._(this.boundary) : super(caseSensitive: true);

  /// Creates a new FormData instance with an auto-generated boundary.
  FormData() : this._(generateBoundary());

  /// The boundary string used to separate multipart sections.
  final String boundary;

  /// Returns a stream of bytes representing the complete multipart form data.
  ///
  /// The stream contains properly formatted multipart content with boundaries,
  /// headers, and entry data according to RFC 2388. Each entry is separated by
  /// the boundary string, and the stream ends with a closing boundary.
  ///
  /// The resulting stream can be used directly as the body of an HTTP request
  /// with Content-Type: multipart/form-data.
  ///
  /// Example:
  /// ```dart
  /// final request = http.Request('POST', Uri.parse('https://example.com/upload'));
  /// request.headers['Content-Type'] = 'multipart/form-data; boundary=${formData.boundary}';
  /// request.bodyBytes = await formData.stream().toList().then((chunks) =>
  ///   Uint8List.fromList(chunks.expand((chunk) => chunk).toList()));
  /// ```
  Stream<Uint8List> stream() async* {
    final lineTerminator = utf8.encode('\r\n');
    final separator = utf8.encode('--$boundary');
    final contentDisposition = utf8.encode('Content-Disposition: form-data;');

    for (final (name, entry) in entries()) {
      yield separator;
      yield lineTerminator;
      yield contentDisposition;
      yield utf8.encode(' name="${Uri.encodeComponent(name)}"');

      if (entry is FormDataFileEntry) {
        yield utf8.encode(
          '; filename="${Uri.encodeComponent(entry.filename)}"',
        );
        yield lineTerminator;
        yield utf8.encode("Content-Type: ${entry.contentType}");
      }

      yield lineTerminator;
      yield lineTerminator;
      yield* entry;
      yield lineTerminator;
    }

    yield separator;
    yield utf8.encode('--');
    yield lineTerminator;
  }
}
