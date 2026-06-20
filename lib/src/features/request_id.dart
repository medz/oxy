import 'dart:async';
import 'dart:math';

import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';

/// Produces a request ID for a request.
typedef RequestIdProvider =
    FutureOr<String?> Function(Request request, Context context);

/// Adds a request ID header when one is available.
final class RequestIdMiddleware implements Middleware {
  RequestIdMiddleware({
    RequestIdProvider? requestIdProvider,
    this.headerName = 'x-request-id',
    this.overrideExisting = false,
  }) : _requestIdProvider = requestIdProvider ?? _defaultRequestId;

  final RequestIdProvider _requestIdProvider;

  /// Header name to write.
  final String headerName;

  /// Whether an existing request ID header should be replaced.
  final bool overrideExisting;

  static final Random _random = Random();

  @override
  Future<Response> intercept(
    Request request,
    Context context,
    Next next,
  ) async {
    if (!overrideExisting && request.headers.has(headerName)) {
      return next(request, context);
    }

    final requestId = await _requestIdProvider(request, context);
    if (requestId == null || requestId.trim().isEmpty) {
      return next(request, context);
    }

    return next(request.withHeader(headerName, requestId.trim()), context);
  }

  static String _defaultRequestId(Request _, Context _) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(0x100000000);
    return '${timestamp.toRadixString(16)}-${randomPart.toRadixString(16).padLeft(8, '0')}';
  }
}
