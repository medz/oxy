import 'abort.dart';
import 'body.dart';
import 'adapter.dart';
import 'default_adapter.dart';
import 'headers.dart';
import 'request.dart';
import 'request_common.dart';
import 'response.dart';

import '_internal/is_web_platform.native.dart'
    if (dart.library.js_interop) '_internal/is_web_platform.web.dart';

/// A configurable HTTP client that provides a high-level interface for making HTTP requests.
///
/// The Oxy class serves as the main entry point for HTTP operations, allowing you to configure
/// adapters and base URLs for consistent request handling across your application.
///
/// Example:
/// ```dart
/// // Create a client with a base URL
/// final client = Oxy(baseURL: Uri.parse('https://api.example.com'));
///
/// // Make a request
/// final request = Request('/users');
/// final response = await client(request);
/// ```
class Oxy {
  /// Creates a new Oxy HTTP client.
  ///
  /// Parameters:
  /// - [adapter]: The adapter to use for making HTTP requests. Defaults to [DefaultAdapter].
  /// - [baseURL]: Optional base URL that will be resolved against relative request URLs.
  const Oxy({this.adapter = const DefaultAdapter(), this.baseURL});

  /// The adapter used for making HTTP requests.
  ///
  /// The adapter handles the actual HTTP communication and can be customized
  /// for different platforms or requirements.
  final Adapter adapter;

  /// Optional base URL for resolving relative request URLs.
  ///
  /// When provided, relative URLs in requests will be resolved against this base URL.
  /// For example, if [baseURL] is `https://api.example.com` and a request is made to
  /// `/users`, the final URL will be `https://api.example.com/users`.
  final Uri? baseURL;

  /// Executes an HTTP request and returns the response.
  ///
  /// This method automatically selects the appropriate adapter based on the platform
  /// and resolves the request URL against the [baseURL] if provided.
  ///
  /// Parameters:
  /// - [request]: The HTTP request to execute.
  ///
  /// Returns a [Future] that completes with the HTTP response.
  Future<Response> call(Request request) {
    final adapter = this.adapter.isSupportWeb && isWebPlatform
        ? this.adapter
        : const DefaultAdapter();
    final url = baseURL?.resolve(request.url) ?? Uri.parse(request.url);

    return adapter.fetch(url, request);
  }
}

/// Default Oxy HTTP client instance.
///
/// This is a convenient, pre-configured instance of [Oxy] that can be used
/// for simple HTTP requests without needing to create your own client instance.
///
/// Example:
/// ```dart
/// final response = await oxy(Request('https://api.example.com/data'));
/// ```
const oxy = Oxy();

/// Makes an HTTP request using the default Oxy client.
///
/// This is a convenience function that creates a [Request] object and executes it
/// using the default [oxy] client instance. It provides a simple, fetch-like API
/// similar to the web platform's fetch() function.
///
/// Parameters:
/// - [url]: The URL to request
/// - [method]: HTTP method (defaults to "GET")
/// - [headers]: Optional HTTP headers
/// - [body]: Optional request body
/// - [signal]: Optional abort signal for canceling the request
/// - [cache]: Cache behavior (defaults to [RequestCache.defaults])
/// - [integrity]: Subresource integrity value
/// - [keepalive]: Whether to keep the connection alive
/// - [mode]: CORS mode (defaults to [RequestMode.cors])
/// - [priority]: Request priority (defaults to [RequestPriority.auto])
/// - [redirect]: Redirect behavior (defaults to [RequestRedirect.follow])
/// - [referrer]: Referrer URL or policy
/// - [referrerPolicy]: Referrer policy (defaults to [ReferrerPolicy.empty])
/// - [credentials]: Credentials behavior (defaults to [RequestCredentials.sameOrigin])
///
/// Returns a [Future] that completes with the HTTP response.
///
/// Example:
/// ```dart
/// // Simple GET request
/// final response = await fetch('https://api.example.com/data');
///
/// // POST request with JSON body
/// final response = await fetch(
///   'https://api.example.com/users',
///   method: 'POST',
///   headers: Headers({'Content-Type': 'application/json'}),
///   body: Body.json({'name': 'John', 'email': 'john@example.com'}),
/// );
/// ```
Future<Response> fetch(
  String url, {
  String method = "GET",
  Headers? headers,
  Body? body,
  AbortSignal? signal,
  RequestCache cache = RequestCache.defaults,
  String integrity = "",
  bool keepalive = false,
  RequestMode mode = RequestMode.cors,
  RequestPriority priority = RequestPriority.auto,
  RequestRedirect redirect = RequestRedirect.follow,
  String referrer = "about:client",
  ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
  RequestCredentials credentials = RequestCredentials.sameOrigin,
}) {
  final request = Request(
    url,
    method: method,
    headers: headers,
    body: body,
    signal: signal,
    cache: cache,
    integrity: integrity,
    keepalive: keepalive,
    mode: mode,
    priority: priority,
    redirect: redirect,
    referrer: referrer,
    referrerPolicy: referrerPolicy,
    credentials: credentials,
  );

  return oxy(request);
}

/// Extension that adds convenient HTTP method shortcuts to the Oxy class.
///
/// This extension provides methods like [get], [post], [put], [delete], and [patch]
/// that simplify making requests with specific HTTP methods.
extension OxyRequestMethods on Oxy {
  /// Makes a GET request to the specified URL.
  ///
  /// This is a convenience method that automatically sets the HTTP method to "GET".
  /// All other parameters are the same as the [fetch] function.
  ///
  /// Example:
  /// ```dart
  /// final client = Oxy(baseURL: Uri.parse('https://api.example.com'));
  /// final response = await client.get('/users');
  /// ```
  Future<Response> get(
    String url, {
    Headers? headers,
    Body? body,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    final request = Request(
      url,
      method: "GET",
      headers: headers,
      body: body,
      signal: signal,
      cache: cache,
      integrity: integrity,
      keepalive: keepalive,
      mode: mode,
      priority: priority,
      redirect: redirect,
      referrer: referrer,
      referrerPolicy: referrerPolicy,
      credentials: credentials,
    );
    return this(request);
  }

  /// Makes a POST request to the specified URL.
  ///
  /// This is a convenience method that automatically sets the HTTP method to "POST".
  /// Commonly used for creating new resources or submitting form data.
  ///
  /// Example:
  /// ```dart
  /// final client = Oxy(baseURL: Uri.parse('https://api.example.com'));
  /// final response = await client.post(
  ///   '/users',
  ///   body: Body.json({'name': 'John', 'email': 'john@example.com'}),
  /// );
  /// ```
  Future<Response> post(
    String url, {
    Headers? headers,
    Body? body,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    final request = Request(
      url,
      method: "POST",
      headers: headers,
      body: body,
      signal: signal,
      cache: cache,
      integrity: integrity,
      keepalive: keepalive,
      mode: mode,
      priority: priority,
      redirect: redirect,
      referrer: referrer,
      referrerPolicy: referrerPolicy,
      credentials: credentials,
    );
    return this(request);
  }

  /// Makes a PUT request to the specified URL.
  ///
  /// This is a convenience method that automatically sets the HTTP method to "PUT".
  /// Commonly used for updating existing resources or creating resources with a specific ID.
  ///
  /// Example:
  /// ```dart
  /// final client = Oxy(baseURL: Uri.parse('https://api.example.com'));
  /// final response = await client.put(
  ///   '/users/123',
  ///   body: Body.json({'name': 'John Updated', 'email': 'john.new@example.com'}),
  /// );
  /// ```
  Future<Response> put(
    String url, {
    Headers? headers,
    Body? body,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    final request = Request(
      url,
      method: "PUT",
      headers: headers,
      body: body,
      signal: signal,
      cache: cache,
      integrity: integrity,
      keepalive: keepalive,
      mode: mode,
      priority: priority,
      redirect: redirect,
      referrer: referrer,
      referrerPolicy: referrerPolicy,
      credentials: credentials,
    );
    return this(request);
  }

  /// Makes a DELETE request to the specified URL.
  ///
  /// This is a convenience method that automatically sets the HTTP method to "DELETE".
  /// Commonly used for deleting existing resources. Note that DELETE requests typically
  /// don't include a body, so this method doesn't have a body parameter.
  ///
  /// Example:
  /// ```dart
  /// final client = Oxy(baseURL: Uri.parse('https://api.example.com'));
  /// final response = await client.delete('/users/123');
  /// ```
  Future<Response> delete(
    String url, {
    Headers? headers,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    final request = Request(
      url,
      method: "DELETE",
      headers: headers,
      signal: signal,
      cache: cache,
      integrity: integrity,
      keepalive: keepalive,
      mode: mode,
      priority: priority,
      redirect: redirect,
      referrer: referrer,
      referrerPolicy: referrerPolicy,
      credentials: credentials,
    );
    return this(request);
  }

  /// Makes a PATCH request to the specified URL.
  ///
  /// This is a convenience method that automatically sets the HTTP method to "PATCH".
  /// Commonly used for partial updates to existing resources. Note that PATCH requests
  /// typically don't include a body, so this method doesn't have a body parameter.
  /// If you need to send a body with a PATCH request, use the [fetch] function directly.
  ///
  /// Example:
  /// ```dart
  /// final client = Oxy(baseURL: Uri.parse('https://api.example.com'));
  /// final response = await client.patch('/users/123/status');
  /// ```
  Future<Response> patch(
    String url, {
    Headers? headers,
    AbortSignal? signal,
    RequestCache cache = RequestCache.defaults,
    String integrity = "",
    bool keepalive = false,
    RequestMode mode = RequestMode.cors,
    RequestPriority priority = RequestPriority.auto,
    RequestRedirect redirect = RequestRedirect.follow,
    String referrer = "about:client",
    ReferrerPolicy referrerPolicy = ReferrerPolicy.empty,
    RequestCredentials credentials = RequestCredentials.sameOrigin,
  }) {
    final request = Request(
      url,
      method: "PATCH",
      headers: headers,
      signal: signal,
      cache: cache,
      integrity: integrity,
      keepalive: keepalive,
      mode: mode,
      priority: priority,
      redirect: redirect,
      referrer: referrer,
      referrerPolicy: referrerPolicy,
      credentials: credentials,
    );
    return this(request);
  }
}
