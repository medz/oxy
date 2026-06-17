import 'dart:convert';

import 'body.dart';
import 'errors.dart';
import 'headers.dart';
import '../options.dart';

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

  final int status;
  final String statusText;
  final Headers headers;
  final Uri url;
  final bool redirected;
  final bool fromCache;
  ResponseBody? body;

  bool get ok => status >= 200 && status <= 299;

  Stream<List<int>> stream() {
    return body?.open() ?? const Stream<List<int>>.empty();
  }

  Future<List<int>> bytes({int? maxBytes}) async {
    return body?.bytes(maxBytes: maxBytes) ?? const <int>[];
  }

  Future<String> text({Encoding encoding = utf8, int? maxBytes}) async {
    return body?.text(encoding: encoding, maxBytes: maxBytes) ?? '';
  }

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

  Future<void> drain({int? maxBytes = 64 * 1024}) async {
    await bytes(maxBytes: maxBytes);
  }

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
