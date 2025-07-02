# Oxy

A modern, feature-rich HTTP client for Dart with Web API compatibility. Built with a flexible adapter architecture and intuitive API design.

[![Oxy Test](https://github.com/medz/webfetch/actions/workflows/oxy-test.yml/badge.svg)](https://github.com/medz/webfetch/actions/workflows/oxy-test.yml)
[![Oxy Version](https://img.shields.io/pub/v/oxy)](https://pub.dev/packages/oxy)

## Features

- 🌐 **Web API Compatible**: Implements familiar web standards like Headers, Request, and Response
- 🚀 **Modern Design**: Clean, intuitive API with method chaining support
- 🔧 **Flexible Architecture**: Configurable adapters for different platforms and requirements
- 📦 **Rich Body Support**: Handle text, JSON, binary data, and FormData seamlessly
- 🎯 **TypeSafe**: Built with modern Dart features and strong typing
- 🔄 **Request Cloning**: Clone requests and responses for reuse
- ⚡ **Streaming Support**: Handle large payloads efficiently with streaming
- 🎛️ **Fine-grained Control**: Configure caching, redirects, credentials, and more

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  oxy: latest
```

Then run:

```bash
dart pub get
```

## Quick Start

### Basic Usage

```dart
import 'package:oxy/oxy.dart';

void main() async {
  // Make a GET request
  final response = await oxy.get('https://jsonplaceholder.typicode.com/posts/1');
  final data = await response.json();
  print(data);
}
```

### With Base URL

```dart
import 'package:oxy/oxy.dart';

void main() async {
  // Create a client with base URL
  final client = Oxy(baseURL: Uri.parse('https://api.example.com'));

  // All requests will be relative to the base URL
  final users = await client.get('/users');
  final posts = await client.get('/posts');
}
```

## HTTP Methods

Oxy provides convenient methods for all standard HTTP verbs:

```dart
final client = Oxy(baseURL: Uri.parse('https://api.example.com'));

// GET request
final users = await client.get('/users');

// POST request with JSON body
final newUser = await client.post(
  '/users',
  body: Body.json({
    'name': 'John Doe',
    'email': 'john@example.com',
  }),
);

// PUT request
final updatedUser = await client.put(
  '/users/123',
  body: Body.json({'name': 'Jane Doe'}),
);

// PATCH request
final patchedUser = await client.patch(
  '/users/123',
  body: Body.json({'email': 'jane@example.com'}),
);

// DELETE request
final deleteResponse = await client.delete('/users/123');
```

## Request Bodies

Oxy supports various body types with a clean API:

```dart
// JSON body
await oxy.post(
  'https://api.example.com/data',
  body: Body.json({'key': 'value'}),
);

// Text body
await oxy.post(
  'https://api.example.com/data',
  body: Body.text('Hello, World!'),
);

// Binary body
await oxy.post(
  'https://api.example.com/data',
  body: Body.bytes(Uint8List.fromList([1, 2, 3])),
);

// Form data
final formData = FormData();
formData.append('name', FormDataEntry.text('John'));
formData.append('file', FormDataEntry.file(fileStream, filename: 'doc.pdf'));

await oxy.post(
  'https://api.example.com/upload',
  body: Body.formData(formData),
);
```

## Headers

Work with HTTP headers using the intuitive Headers class:

```dart
// Set custom headers
final response = await oxy.get(
  'https://api.example.com/data',
  headers: Headers({
    'Authorization': 'Bearer your-token',
    'Content-Type': 'application/json',
    'User-Agent': 'MyApp/1.0',
  }),
);

// Access response headers
final contentType = response.headers.get('content-type');
final allHeaders = response.headers.entries();
```

## Response Handling

```dart
final response = await oxy.get('https://api.example.com/data');

// Check response status
if (response.ok) {
  // Success (200-299)
  print('Request successful: ${response.status}');
} else {
  // Error response
  print('Request failed: ${response.status} ${response.statusText}');
}

// Parse response body
final jsonData = await response.json();      // Parse as JSON
final textData = await response.text();      // Parse as text
final binaryData = await response.bytes();   // Get raw bytes
final formData = await response.formData();  // Parse as form data

// Clone response for multiple consumption
final clonedResponse = response.clone();
```

## Request Cancellation

Use AbortSignal to cancel requests:

```dart
import 'dart:async';

final signal = AbortSignal();

// Cancel the request after 5 seconds
Timer(Duration(seconds: 5), () => signal.abort('Timeout'));

try {
  final response = await oxy.get(
    'https://api.example.com/slow-endpoint',
    signal: signal,
  );

  final data = await response.text();
  print(data);
} catch (e) {
  print('Request was cancelled or failed: $e');
}
```

## Advanced Configuration

```dart
final client = Oxy(
  baseURL: Uri.parse('https://api.example.com'),
  // Use custom adapter if needed
  adapter: MyCustomAdapter(),
);

// Configure individual requests
final response = await client.get(
  '/data',
  cache: RequestCache.noCache,
  credentials: RequestCredentials.include,
  mode: RequestMode.cors,
  redirect: RequestRedirect.follow,
);
```

## Fetch Function

For simple one-off requests, you can use the global `fetch` function:

```dart
import 'package:oxy/oxy.dart';

// Simple GET request
final response = await fetch('https://api.example.com/data');
final data = await response.json();

// POST request
final postResponse = await fetch(
  'https://api.example.com/users',
  method: 'POST',
  body: Body.json({'name': 'John'}),
  headers: Headers({'Authorization': 'Bearer token'}),
);
```

## Adapters

Oxy supports multiple HTTP adapters to suit different needs and platforms. Choose the adapter that best fits your requirements:

| Adapter | Version | Description |
|---------|---------|-------------|
| **Default** | Built-in | Native Dart implementation using `dart:io` HttpClient. Optimized for performance and included by default. |
| **[oxy_http](https://pub.dev/packages/oxy_http)** | [![pub package](https://img.shields.io/pub/v/oxy_http.svg)](https://pub.dev/packages/oxy_http) | HTTP adapter that uses Dart's popular `http` package as the underlying HTTP implementation. |

### Using Custom Adapters

```dart
import 'package:oxy/oxy.dart';
import 'package:oxy_http/oxy_http.dart';

// Use the http package adapter
final client = Oxy(adapter: OxyHttp());

// Use with base URL
final apiClient = Oxy(
  adapter: OxyHttp(),
  baseURL: Uri.parse('https://api.example.com'),
);
```

### Creating Custom Adapters

You can create your own adapter by implementing the `Adapter` interface:

```dart
class MyCustomAdapter implements Adapter {
  @override
  bool get isSupportWeb => false;

  @override
  Future<Response> fetch(Uri url, AdapterRequest request) async {
    // Your custom HTTP implementation
    // ...
  }
}

final client = Oxy(adapter: MyCustomAdapter());
```

## Platform Support

Oxy works on all Dart platforms:

- ✅ **Flutter Mobile** (iOS, Android)
- ✅ **Flutter Desktop** (Windows, macOS, Linux)
- ✅ **Flutter Web**
- ✅ **Dart VM** (Server-side)
- ✅ **Dart Web** (Browser)

The library automatically selects the appropriate adapter based on the platform for optimal performance.

## API Reference

### Core Classes

- **`Oxy`**: Main HTTP client class with configurable adapters and base URL
- **`Request`**: Represents an HTTP request with all its properties
- **`Response`**: Represents an HTTP response with methods to consume the body
- **`Headers`**: Case-insensitive HTTP headers collection
- **`Body`**: Request/response body with support for various content types
- **`FormData`**: Multipart form data for file uploads and form submissions

### Response Properties

```dart
final response = await oxy.get('https://api.example.com/data');

print(response.status);        // HTTP status code (e.g., 200)
print(response.statusText);    // HTTP status text (e.g., "OK")
print(response.ok);            // true if status 200-299
print(response.redirected);    // true if response was redirected
print(response.url);           // final URL after redirects
print(response.headers);       // Response headers
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes and updates.
