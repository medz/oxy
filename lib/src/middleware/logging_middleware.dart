import 'dart:async';

import 'package:ht/ht.dart';

import '../options.dart';

typedef OxyLogPrinter = void Function(String message);

class LoggingMiddleware implements OxyMiddleware {
  LoggingMiddleware({OxyLogPrinter? printer}) : _printer = printer ?? print;

  final OxyLogPrinter _printer;

  @override
  Future<Response> intercept(
    Request request,
    RequestOptions options,
    Next next,
  ) async {
    final stopwatch = Stopwatch()..start();
    _printer('[oxy] -> ${request.method} ${request.url}');

    try {
      final response = await next(request, options);
      stopwatch.stop();
      _printer(
        '[oxy] <- ${response.status} ${request.method} ${request.url} '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      return response;
    } catch (error) {
      stopwatch.stop();
      _printer(
        '[oxy] !! ${request.method} ${request.url} '
        '(${stopwatch.elapsedMilliseconds}ms) $error',
      );
      rethrow;
    }
  }
}
