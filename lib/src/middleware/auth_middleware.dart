import 'dart:async';

import 'package:ht/ht.dart';

import '../options.dart';

typedef AuthTokenProvider =
    FutureOr<String?> Function(Request request, RequestOptions options);

class AuthMiddleware implements OxyMiddleware {
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
    RequestOptions options,
    Next next,
  ) async {
    if (!overrideExisting && request.headers.has(headerName)) {
      return next(request, options);
    }

    final token = await tokenProvider(request, options);
    if (token == null || token.trim().isEmpty) {
      return next(request, options);
    }

    final normalizedToken = token.trim();
    final authValue = (scheme == null || scheme!.isEmpty)
        ? normalizedToken
        : '${scheme!} $normalizedToken';

    final headers = request.headers.clone()..set(headerName, authValue);
    return next(request.copyWith(headers: headers), options);
  }
}
