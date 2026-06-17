import 'dart:js_interop';

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
    var current = request;
    var redirects = 0;
    while (true) {
      final response = await _sendOnce(current, context);
      if (!_isRedirect(response.status)) {
        return response;
      }

      if (context.redirectPolicy.mode == RedirectMode.error) {
        throw StatusError(
          response,
          request: current,
          message: 'Redirect blocked by RedirectPolicy.error.',
        );
      }
      if (context.redirectPolicy.mode == RedirectMode.manual) {
        return response;
      }

      final location = response.headers.get('location');
      if (location == null || location.isEmpty) {
        return response;
      }
      if (redirects >= context.redirectPolicy.maxRedirects) {
        throw StatusError(
          response,
          request: current,
          message: 'Redirect limit exceeded.',
        );
      }

      await response.drain(maxBytes: null);
      current = _redirectRequest(current, response.status, location);
      redirects += 1;
    }
  }

  Future<Response> _sendOnce(Request request, Context context) async {
    if (context.signal?.aborted == true) {
      throw CancelError(reason: context.signal?.reason, request: request);
    }

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
    final streamBody = requestBody?.kind == BodyKind.stream;
    final init = RequestInit(
      method: request.method,
      headers: headers,
      keepalive: context.clientOptions.keepAlive && !streamBody,
      redirect: 'manual',
      signal: controller.signal,
    );

    if (requestBody != null) {
      if (streamBody) {
        init.body = toWebReadableStream(requestBody.open());
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
        transferred: requestBody?.contentLength ?? 0,
        total: requestBody?.contentLength,
      ),
    );

    try {
      final webResponse = await webFetch(WebRequest(request.url, init)).toDart;
      final responseHeaders = _readHeaders(webResponse.headers);
      final total = int.tryParse(responseHeaders.get('content-length') ?? '');
      final body = webResponse.body == null
          ? null
          : toDartStream(
              webResponse.body!,
              onProgress: context.onReceiveProgress,
              total: total,
            );

      return Response(
        body == null ? null : ResponseBody.stream(body, contentLength: total),
        status: webResponse.status,
        statusText: webResponse.statusText,
        headers: responseHeaders,
        url: Uri.tryParse(webResponse.url),
        redirected: webResponse.redirected,
      );
    } catch (error, trace) {
      if (context.signal?.aborted == true) {
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

  Request _redirectRequest(Request request, int status, String location) {
    final uri = request.uri.resolve(location);
    if (status == 303 && request.method.toUpperCase() != 'HEAD') {
      final headers = request.headers.copy()
        ..delete('content-length')
        ..delete('content-type');
      return request.copyWith(
        method: 'GET',
        uri: uri,
        headers: headers,
        clearBody: true,
      );
    }
    return request.copyWith(uri: uri);
  }

  bool _isRedirect(int status) {
    return status >= 300 && status <= 399;
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
