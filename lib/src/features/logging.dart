import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';

typedef LogPrinter = void Function(String message);

final class LoggingMiddleware implements Middleware {
  LoggingMiddleware({LogPrinter? printer}) : _printer = printer ?? print;

  final LogPrinter _printer;

  @override
  Future<Response> intercept(
    Request request,
    Context context,
    Next next,
  ) async {
    final stopwatch = Stopwatch()..start();
    _printer('[oxy] -> ${request.method} ${_redact(request.uri)}');

    try {
      final response = await next(request, context);
      stopwatch.stop();
      _printer(
        '[oxy] <- ${response.status} ${request.method} '
        '${_redact(request.uri)} (${stopwatch.elapsedMilliseconds}ms)',
      );
      return response;
    } catch (error) {
      stopwatch.stop();
      final label = error is RequestError ? error.runtimeType : 'error';
      _printer(
        '[oxy] !! ${request.method} ${_redact(request.uri)} '
        '(${stopwatch.elapsedMilliseconds}ms) $label',
      );
      rethrow;
    }
  }

  String _redact(Uri uri) {
    var sanitized = uri;
    if (sanitized.userInfo.isNotEmpty) {
      sanitized = sanitized.replace(userInfo: '<redacted>');
    }
    if (sanitized.hasQuery) {
      sanitized = sanitized.replace(query: '<redacted>');
    }
    if (sanitized.hasFragment) {
      sanitized = sanitized.replace(fragment: '<redacted>');
    }
    return sanitized.toString();
  }
}
