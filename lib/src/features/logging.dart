import '../core/errors.dart';
import '../core/attributes.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';

/// Receives formatted log messages.
typedef LogPrinter = void Function(String message);

/// Logs request start, response completion, and failures.
///
/// User info, query strings, and fragments are redacted before logging.
final class LoggingMiddleware
    implements RequestTransformer, FinalResponseHandler, FinalErrorHandler {
  LoggingMiddleware({LogPrinter? printer}) : _printer = printer ?? print;

  final LogPrinter _printer;

  @override
  Request onRequest(Request request, Context context) {
    final stopwatch = Stopwatch()..start();
    _printer('[oxy] -> ${request.method} ${_redact(request.uri)}');
    return request.copyWith(
      attributes: request.attributes.set(_loggingStateAttribute, stopwatch),
    );
  }

  @override
  Response onResponse(Request request, Response response, Context context) {
    final stopwatch = request.attributes.get(_loggingStateAttribute);
    if (stopwatch == null) {
      return response;
    }
    stopwatch.stop();
    _printer(
      '[oxy] <- ${response.status} ${request.method} '
      '${_redact(request.uri)} (${stopwatch.elapsedMilliseconds}ms)',
    );
    return response;
  }

  @override
  void onError(Request request, Object error, Context context) {
    final stopwatch = request.attributes.get(_loggingStateAttribute);
    if (stopwatch == null) {
      return;
    }
    stopwatch.stop();
    final label = error is RequestError ? error.runtimeType : 'error';
    _printer(
      '[oxy] !! ${request.method} ${_redact(request.uri)} '
      '(${stopwatch.elapsedMilliseconds}ms) $label',
    );
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

const _loggingStateAttribute = AttributeKey<Stopwatch>('oxy.logging.state');
