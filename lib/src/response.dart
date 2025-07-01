import 'dart:typed_data';

import 'body.dart';
import 'formdata.dart';
import 'headers.dart';
import '_internal/status_map.dart';

/// Represents the response type of an HTTP response.
///
/// This enum indicates how the response was generated and can affect
/// how the response should be handled by the application.
enum ResponseType {
  /// A normal response from the network.
  basic,

  /// A response from a cross-origin request where the response is filtered
  /// for security reasons.
  cors,

  /// A response that indicates an error occurred.
  error,

  /// An opaque response from a cross-origin request that doesn't allow
  /// access to the response data.
  opaque,

  /// An opaque response from a cross-origin request to a different subdomain.
  opaqueRedirect,
}

/// Represents an HTTP response received from a server.
///
/// This class encapsulates all aspects of an HTTP response including the
/// status code, headers, and body content. It extends [Body] to provide
/// convenient methods for consuming the response data in different formats.
///
/// The Response class follows the Fetch API specification and provides
/// properties and methods that are familiar to web developers.
///
/// Example:
/// ```dart
/// final response = Response(
///   status: 200,
///   statusText: 'OK',
///   headers: Headers({'Content-Type': 'application/json'}),
///   body: Stream.value(utf8.encode('{"message": "Hello World"}')),
///   url: 'https://api.example.com/data',
/// );
///
/// if (response.ok) {
///   final data = await response.json();
///   print('Response data: $data');
/// }
/// ```
class Response implements Body {
  /// Creates a new Response instance.
  ///
  /// Parameters:
  /// - [status]: The HTTP status code (defaults to 200)
  /// - [statusText]: The status text (if null, will be looked up from statusMap)
  /// - [headers]: The response headers (defaults to empty Headers)
  /// - [body]: The response body (defaults to empty Body)
  /// - [url]: The URL that was requested (defaults to empty string)
  /// - [redirected]: Whether the response is the result of a redirect (defaults to false)
  /// - [type]: The response type (defaults to ResponseType.basic)
  Response({
    this.status = 200,
    String? statusText,
    Headers? headers,
    Body? body,
    this.url = '',
    this.redirected = false,
    this.type = ResponseType.basic,
  }) : statusText = statusText ?? statusMap[status] ?? 'Unknown',
       headers = headers ?? Headers(),
       _body = body ?? Body(Stream.empty());

  /// Creates a Response representing a network error.
  ///
  /// This factory constructor creates a response that indicates a network
  /// error occurred. The response will have a status of 0, empty headers,
  /// and a type of [ResponseType.error].
  ///
  /// Example:
  /// ```dart
  /// final errorResponse = Response.error();
  /// print(errorResponse.type); // ResponseType.error
  /// print(errorResponse.ok); // false
  /// ```
  factory Response.error() {
    return Response(status: 0, type: ResponseType.error);
  }

  /// Creates a Response representing a redirect.
  ///
  /// This factory constructor creates a response that represents a redirect
  /// to the specified [url]. The response will have the given [status] code
  /// (which should be a redirect status like 301, 302, etc.).
  ///
  /// Parameters:
  /// - [url]: The URL to redirect to
  /// - [status]: The HTTP status code for the redirect (defaults to 302)
  ///
  /// Example:
  /// ```dart
  /// final redirectResponse = Response.redirect(
  ///   'https://example.com/new-location',
  ///   status: 301,
  /// );
  /// ```
  factory Response.redirect(String url, {int status = 302}) {
    final headers = Headers({'Location': url});
    return Response(status: status, headers: headers);
  }

  /// Creates a simple Response with JSON content.
  ///
  /// This factory constructor creates a response with the given [data]
  /// serialized as JSON. The Content-Type header is automatically set
  /// to 'application/json'.
  ///
  /// Parameters:
  /// - [data]: The data to serialize as JSON
  /// - [status]: The HTTP status code (defaults to 200)
  /// - [statusText]: The status text (defaults to 'OK')
  /// - [headers]: Additional headers (Content-Type will be added/overridden)
  ///
  /// Example:
  /// ```dart
  /// final response = Response.json({
  ///   'message': 'Hello World',
  ///   'timestamp': DateTime.now().toIso8601String(),
  /// });
  ///
  /// final data = await response.json();
  /// ```
  factory Response.json(
    Object? data, {
    int status = 200,
    String? statusText,
    Headers? headers,
  }) {
    final body = Body.json(data);
    final responseHeaders = headers ?? Headers();

    // Merge body headers with response headers (response headers take precedence)
    for (final (name, value) in body.headers.entries()) {
      if (!responseHeaders.has(name)) {
        responseHeaders.set(name, value);
      }
    }

    return Response(
      status: status,
      statusText: statusText,
      headers: responseHeaders,
      body: body,
    );
  }

  /// Creates a simple Response with plain text content.
  ///
  /// This factory constructor creates a response with the given [text] content.
  /// The Content-Type header is automatically set to 'text/plain; charset=utf-8'.
  ///
  /// Parameters:
  /// - [text]: The text content
  /// - [status]: The HTTP status code (defaults to 200)
  /// - [statusText]: The status text (defaults to 'OK')
  /// - [headers]: Additional headers (Content-Type will be added/overridden)
  ///
  /// Example:
  /// ```dart
  /// final response = Response.text('Hello, World!');
  /// final content = await response.text();
  /// ```
  factory Response.text(
    String text, {
    int status = 200,
    String? statusText,
    Headers? headers,
  }) {
    final body = Body.text(text);
    final responseHeaders = headers ?? Headers();

    // Merge body headers with response headers (response headers take precedence)
    for (final (name, value) in body.headers.entries()) {
      if (!responseHeaders.has(name)) {
        responseHeaders.set(name, value);
      }
    }

    return Response(
      status: status,
      statusText: statusText,
      headers: responseHeaders,
      body: body,
    );
  }

  /// Creates a simple Response with binary content.
  ///
  /// This factory constructor creates a response with the given [bytes] content.
  /// The Content-Type header is automatically set to 'application/octet-stream'.
  ///
  /// Parameters:
  /// - [bytes]: The binary data
  /// - [status]: The HTTP status code (defaults to 200)
  /// - [statusText]: The status text (defaults to 'OK')
  /// - [headers]: Additional headers (Content-Type will be added/overridden)
  ///
  /// Example:
  /// ```dart
  /// final data = Uint8List.fromList([1, 2, 3, 4]);
  /// final response = Response.bytes(data);
  /// final content = await response.bytes();
  /// ```
  factory Response.bytes(
    Uint8List bytes, {
    int status = 200,
    String? statusText,
    Headers? headers,
  }) {
    final body = Body.bytes(bytes);
    final responseHeaders = headers ?? Headers();

    // Merge body headers with response headers (response headers take precedence)
    for (final (name, value) in body.headers.entries()) {
      if (!responseHeaders.has(name)) {
        responseHeaders.set(name, value);
      }
    }

    return Response(
      status: status,
      statusText: statusText,
      headers: responseHeaders,
      body: body,
    );
  }

  /// Creates a Response with FormData content.
  ///
  /// This factory constructor creates a response with the given [formData].
  /// The Content-Type header is automatically set to 'multipart/form-data'
  /// with the appropriate boundary.
  ///
  /// Parameters:
  /// - [formData]: The FormData to include in the response
  /// - [status]: The HTTP status code (defaults to 200)
  /// - [statusText]: The status text (defaults to 'OK')
  /// - [headers]: Additional headers (Content-Type will be added/overridden)
  ///
  /// Example:
  /// ```dart
  /// final formData = FormData();
  /// formData.append('name', FormDataEntry.text('John'));
  /// final response = Response.formdata(formData);
  /// ```
  factory Response.formdata(
    FormData formData, {
    int status = 200,
    String? statusText,
    Headers? headers,
  }) {
    final body = Body.formdata(formData);
    final responseHeaders = headers ?? Headers();

    // Merge body headers with response headers (response headers take precedence)
    for (final (name, value) in body.headers.entries()) {
      if (!responseHeaders.has(name)) {
        responseHeaders.set(name, value);
      }
    }

    return Response(
      status: status,
      statusText: statusText,
      headers: responseHeaders,
      body: body,
    );
  }

  final Body _body;

  /// The HTTP status code of the response.
  ///
  /// Common status codes include:
  /// - 200: OK
  /// - 201: Created
  /// - 400: Bad Request
  /// - 401: Unauthorized
  /// - 404: Not Found
  /// - 500: Internal Server Error
  final int status;

  /// The HTTP status text corresponding to the status code.
  ///
  /// This is a human-readable description of the status code,
  /// such as 'OK', 'Not Found', 'Internal Server Error', etc.
  final String statusText;

  /// The response headers.
  ///
  /// Provides access to all HTTP headers returned by the server.
  /// Header names are case-insensitive.
  ///
  /// Example:
  /// ```dart
  /// final contentType = response.headers.get('Content-Type');
  /// final cookies = response.headers.getSetCookie();
  /// ```
  @override
  final Headers headers;

  /// The URL of the response.
  ///
  /// This is typically the URL that was requested, but may differ
  /// if redirects occurred during the request.
  final String url;

  /// Whether the response is the result of a redirect.
  ///
  /// Returns `true` if the response was obtained after following
  /// one or more redirects, `false` otherwise.
  final bool redirected;

  /// The type of the response.
  ///
  /// Indicates how the response was generated and can affect
  /// security and access policies.
  final ResponseType type;

  @override
  bool get bodyUsed => _body.bodyUsed;

  @override
  Stream<Uint8List> get body => _body.body;

  /// Whether the response represents a successful HTTP response.
  ///
  /// Returns `true` if the status code is in the range 200-299,
  /// indicating a successful request. Returns `false` for all
  /// other status codes.
  ///
  /// Example:
  /// ```dart
  /// if (response.ok) {
  ///   final data = await response.json();
  ///   // Process successful response
  /// } else {
  ///   print('Request failed with status: ${response.status}');
  /// }
  /// ```
  bool get ok => status >= 200 && status < 300;

  /// Creates a clone of this response.
  ///
  /// This creates a new Response instance with the same status, headers,
  /// and URL, but with a cloned body that can be consumed independently.
  /// This is useful when you need to read the response body multiple times
  /// or pass the response to multiple consumers.
  ///
  /// Example:
  /// ```dart
  /// final originalResponse = await fetch('/api/data');
  /// final clonedResponse = originalResponse.clone();
  ///
  /// // Both responses can now be consumed independently
  /// final text1 = await originalResponse.text();
  /// final text2 = await clonedResponse.text();
  /// ```
  ///
  /// Returns a new [Response] instance with an identical but independent body.
  @override
  Response clone() {
    return Response(
      status: status,
      statusText: statusText,
      headers: Headers(
        headers.entries().fold<Map<String, String>>(
          {},
          (map, entry) => map..[entry.$1] = entry.$2,
        ),
      ),
      body: _body.clone(),
      url: url,
      redirected: redirected,
      type: type,
    );
  }

  @override
  Future<Uint8List> bytes() => _body.bytes();

  @override
  Future json() => _body.json();

  @override
  Future<String> text() => _body.text();

  @override
  String toString() {
    return 'Response($status)';
  }
}
