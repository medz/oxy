# Oxy

A modern, feature-rich HTTP client for Dart with Web API compatibility, supporting fetch-like syntax, request/response handling, and cross-platform adapters.

[![Oxy Test](https://github.com/medz/webfetch/actions/workflows/oxy-test.yml/badge.svg)](https://github.com/medz/webfetch/actions/workflows/oxy-test.yml)
[![Oxy Version](https://img.shields.io/pub/v/oxy)](https://pub.dev/packages/oxy)

## Features

- 🌐 **Web API Compatible**: Implements familiar web standards like Fetch API, Headers, Request, and Response
- 🚀 **Fetch-like Syntax**: Intuitive API similar to browser's `fetch()` function
- 🔧 **Flexible Architecture**: Configurable adapters for different platforms and requirements
- 📦 **Rich Body Support**: Handle text, JSON, binary data, and FormData seamlessly
- 🎯 **Modern Dart**: Built with latest Dart features and best practices
- 🔄 **Request Cloning**: Clone requests and responses for reuse
- ⚡ **Streaming Support**: Handle large payloads efficiently with streaming
- 🎛️ **Fine-grained Control**: Configure caching, redirects, credentials, and more

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  oxy: ^0.0.1
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
  // Simple GET request
  final response = await fetch('https://jsonplaceholder.typicode.com/posts/1');
  final data = await response.json();
  print(data);
}
```

### Using the Oxy Client

```dart
import 'package:oxy/oxy.dart';

void main() async {
  // Create a client with base URL
  final client = Oxy(baseURL: Uri.parse('https://api.example.com'));

  // Make requests using the client
  final response = await client.get('/users');
  final users = await response.json();
  print(users);
}
```

## Examples

### POST Request with JSON

```dart
final response = await fetch(
  'https://api.example.com/users',
  method: 'POST',
  headers: Headers({'Content-Type': 'application/json'}),
  body: Body.json({
    'name': 'John Doe',
    'email': 'john@example.com',
  }),
);

if (response.ok) {
  final user = await response.json();
  print('Created user: $user');
}
```

### Form Data Upload

```dart
final formData = FormData();
formData.append('name', FormDataEntry.text('John'));
formData.append('avatar', FormDataEntry.file(fileStream, filename: 'avatar.jpg'));

final response = await fetch(
  'https://api.example.com/upload',
  method: 'POST',
  body: Body.formData(formData),
);
```

### Request with Custom Headers

```dart
final headers = Headers({
  'Authorization': 'Bearer your-token',
  'User-Agent': 'MyApp/1.0',
});

final response = await fetch(
  'https://api.example.com/protected',
  headers: headers,
);
```

### Using HTTP Method Shortcuts

```dart
final client = Oxy(baseURL: Uri.parse('https://api.example.com'));

// GET request
final users = await client.get('/users');

// POST request
final newUser = await client.post(
  '/users',
  body: Body.json({'name': 'Jane', 'email': 'jane@example.com'}),
);

// PUT request
final updatedUser = await client.put(
  '/users/123',
  body: Body.json({'name': 'Jane Updated'}),
);

// DELETE request
final deleteResponse = await client.delete('/users/123');
```

### Error Handling

```dart
try {
  final response = await fetch('https://api.example.com/data');

  if (!response.ok) {
    print('Request failed with status: ${response.status}');
    return;
  }

  final data = await response.json();
  print(data);
} catch (e) {
  print('Network error: $e');
}
```

### Request Cancellation

```dart
final controller = AbortController();

// Cancel the request after 5 seconds
Timer(Duration(seconds: 5), () => controller.abort());

try {
  final response = await fetch(
    'https://api.example.com/slow-endpoint',
    signal: controller.signal,
  );

  final data = await response.text();
  print(data);
} catch (e) {
  print('Request was cancelled or failed: $e');
}
```

## API Reference

### Core Classes

- **`Oxy`**: Main HTTP client class with configurable adapters and base URL
- **`Request`**: Represents an HTTP request with all its properties
- **`Response`**: Represents an HTTP response with methods to consume the body
- **`Headers`**: Case-insensitive HTTP headers collection
- **`Body`**: Request/response body with support for various content types
- **`FormData`**: Multipart form data for file uploads and form submissions

### Body Types

```dart
// Text body
final textBody = Body.text('Hello, World!');

// JSON body
final jsonBody = Body.json({'key': 'value'});

// Binary body
final binaryBody = Body.bytes(Uint8List.fromList([1, 2, 3]));

// Form data body
final formData = FormData();
formData.append('field', FormDataEntry.text('value'));
final formBody = Body.formData(formData);

// Empty body
final emptyBody = Body.empty();
```

### Response Methods

```dart
final response = await fetch('https://api.example.com/data');

// Check if successful
if (response.ok) {
  // Consume as text
  final text = await response.text();

  // Consume as JSON
  final json = await response.json();

  // Consume as bytes
  final bytes = await response.bytes();

  // Consume as FormData
  final formData = await response.formData();
}

// Clone response for multiple consumption
final cloned = response.clone();
```

## Configuration

### Custom Adapter

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

### Request Configuration

```dart
final response = await fetch(
  'https://api.example.com/data',
  method: 'GET',
  cache: RequestCache.noCache,
  credentials: RequestCredentials.include,
  mode: RequestMode.cors,
  redirect: RequestRedirect.follow,
  referrerPolicy: ReferrerPolicy.noReferrer,
);
```

## Platform Support

Oxy works on all Dart platforms:

- ✅ **Flutter Mobile** (iOS, Android)
- ✅ **Flutter Desktop** (Windows, macOS, Linux)
- ✅ **Flutter Web**
- ✅ **Dart VM** (Server-side)
- ✅ **Dart Web** (Browser)

The library automatically selects the appropriate adapter based on the platform for optimal performance.

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes and updates.
