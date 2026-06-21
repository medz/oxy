import 'dart:async';

import '../core/request.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';

/// Resolves an authentication token for a request.
typedef AuthTokenProvider =
    FutureOr<String?> Function(Request request, Context context);

/// Adds an authorization header when a token is available.
final class AuthMiddleware implements RequestTransformer {
  AuthMiddleware({
    required this.tokenProvider,
    this.scheme = 'Bearer',
    this.headerName = 'authorization',
    this.overrideExisting = false,
  });

  /// Creates middleware that always uses [token].
  AuthMiddleware.staticToken(
    String token, {
    String? scheme = 'Bearer',
    String headerName = 'authorization',
    bool overrideExisting = false,
  }) : this(
         tokenProvider: (_, _) => token,
         scheme: scheme,
         headerName: headerName,
         overrideExisting: overrideExisting,
       );

  /// Provider used to resolve the token.
  final AuthTokenProvider tokenProvider;

  /// Authentication scheme prepended to the token, or `null` for raw tokens.
  final String? scheme;

  /// Header name to write.
  final String headerName;

  /// Whether an existing header should be replaced.
  final bool overrideExisting;

  @override
  Future<Request> onRequest(Request request, Context context) async {
    if (!overrideExisting && request.headers.has(headerName)) {
      return request;
    }

    final token = await tokenProvider(request, context);
    if (token == null || token.trim().isEmpty) {
      return request;
    }

    final value = scheme == null || scheme!.isEmpty
        ? token.trim()
        : '${scheme!} ${token.trim()}';

    return request.withHeader(headerName, value);
  }
}
