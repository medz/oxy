import 'dart:async';

import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';

typedef AuthTokenProvider =
    FutureOr<String?> Function(Request request, Context context);

final class AuthMiddleware implements Middleware {
  AuthMiddleware({
    required this.tokenProvider,
    this.scheme = 'Bearer',
    this.headerName = 'authorization',
    this.overrideExisting = false,
  });

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

  final AuthTokenProvider tokenProvider;
  final String? scheme;
  final String headerName;
  final bool overrideExisting;

  @override
  Future<Response> intercept(
    Request request,
    Context context,
    Next next,
  ) async {
    if (!overrideExisting && request.headers.has(headerName)) {
      return next(request, context);
    }

    final token = await tokenProvider(request, context);
    if (token == null || token.trim().isEmpty) {
      return next(request, context);
    }

    final value = scheme == null || scheme!.isEmpty
        ? token.trim()
        : '${scheme!} ${token.trim()}';

    return next(request.withHeader(headerName, value), context);
  }
}
