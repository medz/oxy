import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../core/body.dart';
import '../core/errors.dart';
import '../core/headers.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../options.dart';
import '../pipeline/context.dart';
import '../policies.dart';
import 'capability.dart';
import 'transport.dart';
import 'web_stream_utils.dart';

Transport createTransport({bool keepAlive = true}) => WebTransport();

extension type IteratorReturnResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSAny? get value;
}

extension type ArrayIterator._(JSObject _) implements JSObject {
  external IteratorReturnResult next();
}

@JS('Array')
extension type JSArrayStatic._(JSObject _) {
  external static bool isArray(JSAny? value);
}

@JS('Headers')
extension type WebHeaders._(JSObject _) implements JSObject {
  external factory WebHeaders();
  external void append(String name, String value);
  external ArrayIterator entries();
}

@JS('AbortSignal')
extension type WebAbortSignal._(JSObject _) implements JSObject {}

@JS('AbortController')
extension type WebAbortController._(JSObject _) implements JSObject {
  external factory WebAbortController();
  external WebAbortSignal get signal;
  external void abort([JSAny? reason]);
}

extension type RequestInit._(JSObject _) implements JSObject {
  external factory RequestInit({
    String? method,
    WebHeaders? headers,
    JSAny? body,
    bool? keepalive,
    String? redirect,
    String? duplex,
    WebAbortSignal? signal,
  });

  external JSAny? body;
  external String? duplex;
}

@JS('Request')
extension type WebRequest._(JSObject _) implements JSObject {
  external factory WebRequest(String input, RequestInit init);
}

@JS('Response')
extension type WebResponse._(JSObject _) implements JSObject {
  external int get status;
  external String get statusText;
  external String get url;
  external String get type;
  external bool get redirected;
  external WebHeaders get headers;
  external ReadableStream? get body;
}

@JS('fetch')
external JSPromise<WebResponse> webFetch(WebRequest request);

final class WebTransport implements Transport {
  @override
  PlatformCapability get capability => PlatformCapability.web;

  @override
  Future<void> close() async {}

  @override
  Future<Response> send(Request request, Context context) async {
    return _sendOnce(request, context);
  }

  Future<Response> _sendOnce(Request request, Context context) async {
    if (context.signal?.aborted == true) {
      throw CancelError(reason: context.signal?.reason, request: request);
    }
    _validateRedirectPolicy(request, context);

    final headers = WebHeaders();
    for (final entry in request.headers) {
      if (_isForbiddenRequestHeader(entry.key)) {
        continue;
      }
      headers.append(entry.key, entry.value);
    }

    final controller = WebAbortController();
    _bindAbort(controller, context);

    final requestBody = request.body;
    final streamBody = streamsRequestBody(requestBody);
    final contentLength = knownBodyLength(requestBody);
    final requestBodySent =
        streamBody && context.timeoutPolicy.firstByte != null
        ? Completer<void>()
        : null;
    final init = RequestInit(
      method: request.method,
      headers: headers,
      keepalive: context.clientOptions.keepAlive && requestBody == null,
      redirect: _redirectMode(context.redirectPolicy),
      signal: controller.signal,
    );

    if (requestBody != null) {
      if (streamBody) {
        final stream = _withSendTimeout(requestBody.stream(), context, request);
        init.body = toWebReadableStream(
          requestBodySent == null
              ? stream
              : _trackRequestBodySent(stream, requestBodySent),
        );
        init.duplex = 'half';
      } else {
        final bytesFuture = requestBody.bytes();
        final sendTimeout = context.timeoutPolicy.send;
        init.body =
            (sendTimeout == null
                    ? await bytesFuture
                    : await bytesFuture.timeout(
                        sendTimeout,
                        onTimeout: () {
                          throw TimeoutError(
                            phase: TimeoutPhase.send,
                            duration: sendTimeout,
                            request: request,
                            sent: true,
                          );
                        },
                      ))
                .toJS;
      }
    }

    context.onSendProgress?.call(
      TransferProgress(
        transferred: streamBody ? 0 : (contentLength ?? 0),
        total: contentLength,
      ),
    );

    try {
      final webResponse = await _withFirstByteTimeout(
        webFetch(WebRequest(request.url, init)).toDart,
        requestBodySent?.future,
        controller,
        request,
        context,
      );
      final responseHeaders = _readHeaders(webResponse.headers);
      final total = int.tryParse(responseHeaders.get('content-length') ?? '');
      final body = webResponse.body == null
          ? null
          : toDartStream(
              webResponse.body!,
              request: request,
              signal: context.signal,
              onProgress: context.onReceiveProgress,
              total: total,
            );

      if (body == null) {
        context.onReceiveProgress?.call(
          TransferProgress(transferred: 0, total: total ?? 0),
        );
      }

      final response = Response(
        body == null ? null : ResponseBody.stream(body, contentLength: total),
        status: webResponse.status,
        statusText: webResponse.statusText,
        headers: responseHeaders,
        url: Uri.tryParse(webResponse.url),
        redirected: webResponse.redirected,
      );
      if (context.redirectPolicy.mode == RedirectMode.error &&
          (_isRedirect(response.status) ||
              webResponse.type == 'opaqueredirect')) {
        throw StatusError(
          response,
          request: request,
          message: 'Redirect blocked by RedirectPolicy.error.',
        );
      }
      return response;
    } catch (error, trace) {
      if (context.signal?.aborted == true) {
        if (context.signal?.reason case final TimeoutError timeoutError) {
          throw timeoutError;
        }
        throw CancelError(
          reason: context.signal?.reason,
          request: request,
          trace: trace,
        );
      }
      if (error is RequestError) {
        rethrow;
      }
      throw NetworkError(
        error.toString(),
        request: request,
        cause: error,
        trace: trace,
      );
    }
  }

  Stream<Uint8List> _withSendTimeout(
    Stream<Uint8List> source,
    Context context,
    Request request,
  ) async* {
    final timeout = context.timeoutPolicy.send;
    if (timeout == null) {
      yield* source;
      return;
    }

    final iterator = StreamIterator<Uint8List>(source);
    Future<void>? cancelFuture;
    Future<void> cancelIterator() {
      return cancelFuture ??= iterator.cancel();
    }

    TimeoutError? sendTimeoutError;
    final sendTimer = Timer(timeout, () {
      final timeoutError = TimeoutError(
        phase: TimeoutPhase.send,
        duration: timeout,
        request: request,
        sent: true,
      );
      sendTimeoutError = timeoutError;
      context.signal?.abort(timeoutError);
      unawaited(cancelIterator());
    });

    try {
      while (await iterator.moveNext()) {
        final timeoutError = sendTimeoutError;
        if (timeoutError != null) {
          throw timeoutError;
        }
        yield iterator.current;
      }
      final timeoutError = sendTimeoutError;
      if (timeoutError != null) {
        throw timeoutError;
      }
    } catch (_) {
      final timeoutError = sendTimeoutError;
      if (timeoutError != null) {
        throw timeoutError;
      }
      rethrow;
    } finally {
      sendTimer.cancel();
      await cancelIterator();
    }
  }

  Stream<Uint8List> _trackRequestBodySent(
    Stream<Uint8List> source,
    Completer<void> sent,
  ) async* {
    try {
      await for (final chunk in source) {
        yield chunk;
      }
      if (!sent.isCompleted) {
        sent.complete();
      }
    } catch (error, trace) {
      if (!sent.isCompleted) {
        sent.completeError(error, trace);
      }
      rethrow;
    }
  }

  Future<WebResponse> _withFirstByteTimeout(
    Future<WebResponse> fetchFuture,
    Future<void>? requestBodySent,
    WebAbortController controller,
    Request request,
    Context context,
  ) async {
    final timeout = context.timeoutPolicy.firstByte;
    if (timeout == null) {
      return fetchFuture;
    }

    if (requestBodySent != null) {
      final fetchReady = Object();
      final first = await Future.any<Object>([
        fetchFuture.then((_) => fetchReady),
        requestBodySent.then((_) => Object(), onError: (_, _) => Object()),
      ]);
      if (identical(first, fetchReady)) {
        return fetchFuture;
      }
    }

    return fetchFuture.timeout(
      timeout,
      onTimeout: () {
        final timeoutError = TimeoutError(
          phase: TimeoutPhase.firstByte,
          duration: timeout,
          request: request,
          sent: true,
        );
        context.signal?.abort(timeoutError);
        controller.abort(timeoutError.toString().toJS);
        throw timeoutError;
      },
    );
  }

  Headers _readHeaders(WebHeaders source) {
    final headers = Headers();
    final iterator = source.entries();

    while (true) {
      final result = iterator.next();
      if (result.done) {
        break;
      }

      final value = result.value;
      if (value == null ||
          value.isUndefinedOrNull ||
          !JSArrayStatic.isArray(value)) {
        continue;
      }

      final pair = (value as JSArray<JSString>).toDart;
      if (pair.length >= 2) {
        headers.append(pair[0].toDart, pair[1].toDart);
      }
    }

    return headers;
  }

  void _bindAbort(WebAbortController controller, Context context) {
    final signal = context.signal;
    if (signal == null) {
      return;
    }

    if (signal.aborted) {
      controller.abort(signal.reason?.toString().toJS);
      return;
    }

    signal.onAbort(() {
      controller.abort(signal.reason?.toString().toJS);
    });
  }

  void _validateRedirectPolicy(Request request, Context context) {
    final policy = context.redirectPolicy;
    if (policy.mode == RedirectMode.follow &&
        policy.maxRedirects != RedirectPolicy.follow.maxRedirects) {
      throw PolicyError(
        'Browser Fetch does not expose redirect chains, so custom '
        'RedirectPolicy.maxRedirects cannot be enforced on web.',
        request: request,
      );
    }
  }

  String _redirectMode(RedirectPolicy policy) {
    return switch (policy.mode) {
      RedirectMode.follow => 'follow',
      RedirectMode.manual => 'manual',
      RedirectMode.error => 'manual',
    };
  }

  bool _isRedirect(int status) {
    return switch (status) {
      301 || 302 || 303 || 307 || 308 => true,
      _ => false,
    };
  }

  bool _isForbiddenRequestHeader(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('proxy-') ||
        lower.startsWith('sec-') ||
        _forbiddenRequestHeaders.contains(lower);
  }
}

const Set<String> _forbiddenRequestHeaders = <String>{
  'accept-charset',
  'accept-encoding',
  'access-control-request-headers',
  'access-control-request-method',
  'connection',
  'content-length',
  'cookie',
  'cookie2',
  'date',
  'dnt',
  'expect',
  'host',
  'keep-alive',
  'origin',
  'referer',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'via',
};
