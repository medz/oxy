import 'attributes.dart';
import 'body.dart';
import 'headers.dart';
import '../options.dart';

/// An immutable HTTP request prepared for Oxy's pipeline.
///
/// A request stores the method, URI, headers, optional [Body], and
/// per-request [RequestOptions]. Use [copyWith] to derive a modified request in
/// middleware; copy existing headers with `Headers(request.headers)` before
/// changing them.
///
/// ```dart
/// final request = Request(
///   '/users',
///   method: 'POST',
///   body: Body.fromJson({'name': 'oxy'}),
/// );
/// ```
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

  /// The HTTP method.
  final String method;

  /// The request URI before client base URL resolution.
  final Uri uri;

  /// The request headers.
  final Headers headers;

  /// The optional request body.
  final Body? body;

  /// Per-request options.
  final RequestOptions options;

  /// Request attributes used by middleware and transports.
  final Attributes attributes;

  /// The string form of [uri].
  String get url => uri.toString();

  /// Creates a copy with selected values replaced.
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
      headers: Headers(headers ?? this.headers),
      body: clearBody ? null : body ?? this.body,
      options: options ?? this.options,
      attributes: attributes ?? this.attributes,
    );
  }

  static Uri _parseUri(Object input) {
    return switch (input) {
      Uri() => input,
      String() => Uri.parse(input),
      _ => throw ArgumentError.value(input, 'url', 'Expected Uri or String.'),
    };
  }
}
