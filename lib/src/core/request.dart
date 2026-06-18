import 'attributes.dart';
import 'body.dart';
import 'headers.dart';
import '../options.dart';

final class Request {
  Request(
    Object url, {
    String method = 'GET',
    HeadersInit? headers,
    Object? body,
    RequestOptions? options,
    Attributes attributes = const Attributes(),
  }) : this._(
         method: method,
         uri: _parseUri(url),
         headers: Headers(headers),
         body: Body.from(body),
         options: options ?? const RequestOptions(),
         attributes: attributes,
       );

  const Request._({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    required this.options,
    required this.attributes,
  });

  final String method;
  final Uri uri;
  final Headers headers;
  final Body? body;
  final RequestOptions options;
  final Attributes attributes;

  String get url => uri.toString();

  Request copyWith({
    String? method,
    Uri? uri,
    HeadersInit? headers,
    Body? body,
    bool clearBody = false,
    RequestOptions? options,
    Attributes? attributes,
  }) {
    return Request._(
      method: method ?? this.method,
      uri: uri ?? this.uri,
      headers: headers == null ? this.headers.copy() : Headers(headers),
      body: clearBody ? null : body ?? this.body,
      options: options ?? this.options,
      attributes: attributes ?? this.attributes,
    );
  }

  Request withHeader(String name, Object value) {
    final nextHeaders = headers.copy()..set(name, value);
    return copyWith(headers: nextHeaders);
  }

  static Uri _parseUri(Object input) {
    return switch (input) {
      Uri() => input,
      String() => Uri.parse(input),
      _ => throw ArgumentError.value(input, 'url', 'Expected Uri or String.'),
    };
  }
}
