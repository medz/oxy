import 'dart:async';
import 'dart:math';

import 'package:ht/ht.dart';

import '../options.dart';

typedef RequestIdProvider =
    FutureOr<String?> Function(Request request, RequestOptions options);

class RequestIdMiddleware implements OxyMiddleware {
  RequestIdMiddleware({
    RequestIdProvider? requestIdProvider,
    this.headerName = 'x-request-id',
    this.overrideExisting = false,
  }) : _requestIdProvider = requestIdProvider ?? _defaultRequestId;

  final RequestIdProvider _requestIdProvider;
  final String headerName;
  final bool overrideExisting;

  static final Random _random = Random.secure();

  @override
  Future<Response> intercept(
    Request request,
    RequestOptions options,
    Next next,
  ) async {
    if (!overrideExisting && request.headers.has(headerName)) {
      return next(request, options);
    }

    final requestId = await _requestIdProvider(request, options);
    if (requestId == null || requestId.trim().isEmpty) {
      return next(request, options);
    }

    final headers = request.headers.clone()..set(headerName, requestId.trim());
    return next(request.copyWith(headers: headers), options);
  }

  static String _defaultRequestId(Request _, RequestOptions _) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(0x100000000);
    return '${timestamp.toRadixString(16)}-${randomPart.toRadixString(16).padLeft(8, '0')}';
  }
}
