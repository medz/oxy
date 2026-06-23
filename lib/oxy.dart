/// A policy-first HTTP client for Dart and Flutter applications.
///
/// Import this library when you want to send one-off requests with [fetch],
/// build a long-lived [Client] for a reusable API client, configure retry and
/// timeout policies, compose middleware, or test network code with
/// `package:oxy/testing.dart`.
///
/// ```dart
/// import 'package:oxy/oxy.dart';
///
/// Future<void> main() async {
///   final client = Client(
///     ClientOptions(baseUrl: Uri.parse('https://api.example.com')),
///   );
///
///   try {
///     final response = await client.get('/health');
///     print(response.status);
///   } finally {
///     await client.close();
///   }
/// }
/// ```
library;

export 'package:ht/ht.dart'
    show Blob, BlobPart, File, FormData, Multipart, URLSearchParams;

export 'src/client.dart';
export 'src/core/abort.dart';
export 'src/core/attributes.dart';
export 'src/core/body.dart';
export 'src/core/errors.dart';
export 'src/core/headers.dart';
export 'src/core/request.dart';
export 'src/core/response.dart';
export 'src/core/result.dart';
export 'src/features/auth.dart';
export 'src/features/cache.dart';
export 'src/features/cookie.dart';
export 'src/features/cookie_middleware.dart';
export 'src/features/logging.dart';
export 'src/features/request_id.dart';
export 'src/options.dart';
export 'src/pipeline/context.dart';
export 'src/pipeline/events.dart';
export 'src/pipeline/middleware.dart';
export 'src/policies.dart';
export 'src/transport/capability.dart';
export 'src/transport/transport.dart';
