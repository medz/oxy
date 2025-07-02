import 'dart:async';
import 'dart:typed_data';

import 'package:oxy/oxy.dart' as oxy;
import 'package:http/http.dart' as http;

// Helper function to fire and forget futures
void unawaited(Future<void> future) {
  // Ignore the future - fire and forget
}

/// An HTTP adapter implementation for the [Oxy](https://github.com/medz/oxy) package that uses the `http` package.
///
/// This adapter bridges between the Oxy API and Dart's standard HTTP client,
/// allowing Oxy to make HTTP requests using the `http` package as the underlying transport.
class OxyHttp implements oxy.Adapter {
  /// Creates a new [OxyHttp] adapter.
  ///
  /// [client] - Optional HTTP client to use. If not provided, a default client will be created.
  /// [isSupportWeb] - Whether this adapter supports web platforms. Defaults to true.
  OxyHttp({http.Client? client, this.isSupportWeb = true}) : _client = client;

  /// Whether this adapter supports web platforms.
  @override
  final bool isSupportWeb;

  http.Client? _client;

  /// Gets the HTTP client, creating a default one if none was provided.
  http.Client get client => _client ??= http.Client();

  /// Fetches a resource from the given URL using the provided request configuration.
  ///
  /// [url] - The URL to fetch from.
  /// [request] - The adapter request containing method, headers, body, and other options.
  ///
  /// Returns an [oxy.Response] with the response data.
  /// Throws the response if redirect handling is set to error and a redirect occurs.
  @override
  Future<oxy.Response> fetch(Uri url, oxy.AdapterRequest request) async {
    final httpRequest = http.StreamedRequest(request.method, url);

    // Set up headers
    final requestHeaderNames = request.headers
        .keys()
        .map((e) => e.toLowerCase())
        .toSet();
    for (final name in requestHeaderNames) {
      final values = request.headers.getAll(name);
      if (values.isEmpty) continue;
      httpRequest.headers[name] = values.join(', ');
    }

    // Configure redirect behavior
    httpRequest.followRedirects =
        request.redirect == oxy.RequestRedirect.follow;
    httpRequest.maxRedirects = request.redirect == oxy.RequestRedirect.manual
        ? 0
        : 5;
    httpRequest.persistentConnection = request.keepalive;

    try {
      await for (final event in request.body) {
        httpRequest.sink.add(event);
      }
    } catch (e) {
      request.signal.abort(e);
    } finally {
      unawaited(httpRequest.sink.close());
    }

    // Send the request
    final http.StreamedResponse httpResponse = await client
        .send(httpRequest)
        .catchError((e) {
          request.signal.abort(e);
          throw e;
        });

    final body = oxy.Body(
      httpResponse.stream.map((event) {
        if (event is Uint8List) return event;
        return Uint8List.fromList(event);
      }),
    );

    // Set content-type header if present
    if (httpResponse.headers.containsKey('content-type')) {
      body.headers.set("content-type", httpResponse.headers['content-type']!);
    }

    // Create Oxy response
    final response = oxy.Response(
      status: httpResponse.statusCode,
      statusText: httpResponse.reasonPhrase,
      redirected: httpResponse.isRedirect,
      url: url.toString(),
      body: body,
    );

    // Copy response headers
    for (final entry in httpResponse.headersSplitValues.entries) {
      for (final value in entry.value) {
        response.headers.append(entry.key, value);
      }
    }

    // Handle redirect error policy
    if (request.redirect == oxy.RequestRedirect.error && response.redirected) {
      throw response;
    }

    return response;
  }
}
