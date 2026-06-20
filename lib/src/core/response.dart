import 'dart:convert';

import 'body.dart';
import 'errors.dart';
import 'headers.dart';
import '../options.dart';

/// An HTTP response returned by Oxy.
///
/// A response owns status metadata, headers, and an optional [ResponseBody].
/// Response instances are immutable; use [copyWith] or [buffered] when a
/// middleware needs to derive a modified response.
///
/// Response bodies can be replayable or one-shot. Convenience readers such as
/// [text], [json], and [bytes] consume the body stream.
final class Response {
  Response(
    Object? body, {
    this.status = 200,
    this.statusText = 'OK',
    HeadersInit? headers,
    Uri? url,
    this.redirected = false,
    this.fromCache = false,
  }) : body = _responseBodyFrom(body),
       headers = Headers(headers),
       url = url ?? Uri();

  /// Creates a replayable response from raw [bytes].
  Response.bytes(
    List<int> bytes, {
    this.status = 200,
    this.statusText = 'OK',
    HeadersInit? headers,
    Uri? url,
    this.redirected = false,
    this.fromCache = false,
  }) : body = ResponseBody.fromBytes(bytes),
       headers = Headers(headers),
       url = url ?? Uri();

  /// Creates a replayable UTF-8 text response.
  Response.text(
    String text, {
    this.status = 200,
    this.statusText = 'OK',
    HeadersInit? headers,
    Uri? url,
    this.redirected = false,
    this.fromCache = false,
  }) : body = ResponseBody.fromText(text),
       headers = _headersWithDefault(
         headers,
         'content-type',
         'text/plain; charset=utf-8',
       ),
       url = url ?? Uri();

  /// Creates a replayable JSON response.
  Response.json(
    Object? value, {
    this.status = 200,
    this.statusText = 'OK',
    HeadersInit? headers,
    Uri? url,
    this.redirected = false,
    this.fromCache = false,
  }) : body = ResponseBody.fromText(jsonEncode(value)),
       headers = _headersWithDefault(
         headers,
         'content-type',
         'application/json; charset=utf-8',
       ),
       url = url ?? Uri();

  /// Creates a one-shot streaming response.
  Response.stream(
    Stream<List<int>> stream, {
    this.status = 200,
    this.statusText = 'OK',
    HeadersInit? headers,
    Uri? url,
    this.redirected = false,
    this.fromCache = false,
    int? contentLength,
  }) : body = ResponseBody.stream(stream, contentLength: contentLength),
       headers = Headers(headers),
       url = url ?? Uri();

  /// The HTTP status code.
  final int status;

  /// The HTTP status reason phrase.
  final String statusText;

  /// The response headers.
  final Headers headers;

  /// The final response URL, when known.
  final Uri url;

  /// Whether the response followed at least one redirect.
  final bool redirected;

  /// Whether the response was served by `CacheMiddleware`.
  final bool fromCache;

  /// The optional response body.
  final ResponseBody? body;

  /// Whether [status] is in the 2xx range.
  bool get ok => status >= 200 && status <= 299;

  /// Opens the response body stream.
  ///
  /// Returns an empty stream when [body] is `null`.
  Stream<List<int>> stream() {
    return body?.open() ?? const Stream<List<int>>.empty();
  }

  /// Reads the response body as bytes.
  ///
  /// Throws [BodyTooLargeError] if [maxBytes] is set and the body exceeds it.
  Future<List<int>> bytes({int? maxBytes}) async {
    return body?.bytes(maxBytes: maxBytes) ?? const <int>[];
  }

  /// Reads the response body as text using [encoding].
  Future<String> text({Encoding encoding = utf8, int? maxBytes}) async {
    return body?.text(encoding: encoding, maxBytes: maxBytes) ?? '';
  }

  /// Reads and decodes the response body as JSON.
  ///
  /// Throws [DecodeError] when decoding fails.
  Future<T> json<T>({int? maxBytes}) async {
    try {
      return await body?.json(maxBytes: maxBytes) as T;
    } catch (error, trace) {
      throw DecodeError(
        'Failed to decode response body as JSON.',
        response: this,
        cause: error,
        trace: trace,
      );
    }
  }

  /// Reads JSON and maps it to [T].
  ///
  /// If [decoder] is omitted, the decoded payload is cast to [T].
  /// Throws [DecodeError] when JSON decoding or mapping fails.
  Future<T> decode<T>({Decoder<T>? decoder, int? maxBytes}) async {
    Object? payload;
    try {
      payload = await json<Object?>(maxBytes: maxBytes);
    } catch (error, trace) {
      if (error is DecodeError) {
        rethrow;
      }
      throw DecodeError(
        'Failed to decode response body as JSON.',
        response: this,
        cause: error,
        trace: trace,
      );
    }

    try {
      return decoder == null ? payload as T : decoder(payload);
    } catch (error, trace) {
      throw DecodeError(
        'Failed to map decoded payload to `$T`.',
        response: this,
        cause: error,
        trace: trace,
      );
    }
  }

  /// Reads and discards the response body.
  ///
  /// This is useful before retrying or closing a response. Throws
  /// [BodyTooLargeError] if [maxBytes] is set and the body exceeds it.
  Future<void> drain({int? maxBytes = 64 * 1024}) async {
    var transferred = 0;
    await for (final chunk in stream()) {
      transferred += chunk.length;
      if (maxBytes != null && transferred > maxBytes) {
        throw BodyTooLargeError(limit: maxBytes, response: this);
      }
    }
  }

  /// Returns a replayable response by buffering the body into memory.
  ///
  /// Throws [BodyTooLargeError] if [maxBytes] is set and the body exceeds it.
  Future<Response> buffered({int? maxBytes = 1024 * 1024}) async {
    final data = await bytes(maxBytes: maxBytes);
    return Response.bytes(
      data,
      status: status,
      statusText: statusText,
      headers: headers,
      url: url,
      redirected: redirected,
      fromCache: fromCache,
    );
  }

  /// Creates a copy with selected values replaced.
  ///
  /// Use [clearBody] to create a response without a body.
  Response copyWith({
    Object? body,
    bool clearBody = false,
    int? status,
    String? statusText,
    HeadersInit? headers,
    Uri? url,
    bool? redirected,
    bool? fromCache,
  }) {
    return Response(
      clearBody ? null : body ?? this.body,
      status: status ?? this.status,
      statusText: statusText ?? this.statusText,
      headers: headers ?? this.headers,
      url: url ?? this.url,
      redirected: redirected ?? this.redirected,
      fromCache: fromCache ?? this.fromCache,
    );
  }

  static Headers _headersWithDefault(
    HeadersInit? headers,
    String name,
    String value,
  ) {
    final next = Headers(headers);
    if (!next.has(name)) {
      next.set(name, value);
    }
    return next;
  }

  static ResponseBody? _responseBodyFrom(Object? value) {
    return switch (value) {
      null => null,
      ResponseBody() => value,
      String() => ResponseBody.fromText(value),
      List<int>() => ResponseBody.fromBytes(value),
      Stream<List<int>>() => ResponseBody.stream(value),
      _ => ResponseBody.fromText(value.toString()),
    };
  }
}
