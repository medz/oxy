import 'dart:async';
import 'dart:math';

import '../core/headers.dart';
import '../core/request.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';

/// Produces a request ID for a request.
typedef RequestIdProvider =
    FutureOr<String?> Function(Request request, Context context);

/// Adds a request ID header when one is available.
final class RequestIdMiddleware implements RequestTransformer {
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
  Future<Request> onRequest(Request request, Context context) async {
    if (!overrideExisting && request.headers.has(headerName)) {
      return request;
    }

    final requestId = await _requestIdProvider(request, context);
    if (requestId == null || requestId.trim().isEmpty) {
      return request;
    }

    return request.copyWith(
      headers: Headers(request.headers)..set(headerName, requestId.trim()),
    );
  }

  static String _defaultRequestId(Request _, Context _) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(0x100000000);
    return '${timestamp.toRadixString(16)}-${randomPart.toRadixString(16).padLeft(8, '0')}';
  }
}
