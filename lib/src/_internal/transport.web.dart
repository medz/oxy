import 'dart:js_interop';

import 'package:ht/ht.dart';

import '../errors.dart';
import '../options.dart';
import 'web_stream_utils.dart';

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
extension type AbortController._(JSObject _) implements JSObject {
  external factory AbortController();
  external WebAbortSignal get signal;
  external void abort([JSAny? reason]);
}

extension type RequestInit._(JSObject _) implements JSObject {
  external factory RequestInit({
    String? method,
    WebHeaders? headers,
    ReadableStream? body,
    bool? keepalive,
    String? redirect,
    WebAbortSignal? signal,
  });

  external ReadableStream? body;
  external WebAbortSignal? signal;
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

Future<Response> fetchTransport(Request request, RequestOptions options) async {
  options.signal?.throwIfAborted();

  final headers = WebHeaders();
  for (final entry in request.headers) {
    headers.append(entry.key, entry.value);
  }

  options.onSendProgress?.call(
    const TransferProgress(transferred: 0, total: null),
  );

  final controller = AbortController();
  _bindAbort(controller, options);

  final init = RequestInit(
    method: request.method,
    headers: headers,
    keepalive: options.keepAlive,
    redirect: _mapRedirect(options.redirectPolicy ?? RedirectPolicy.follow),
    signal: controller.signal,
  );

  final requestBody = request.body;
  if (requestBody != null) {
    init.body = toWebReadableStream(requestBody);
  }

  try {
    final webResponse = await webFetch(
      WebRequest(request.url.toString(), init),
    ).toDart;

    final responseHeaders = Headers();
    final iterator = webResponse.headers.entries();

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
      if (pair.length < 2) {
        continue;
      }

      responseHeaders.append(pair[0].toDart, pair[1].toDart);
    }

    final total = int.tryParse(responseHeaders.get('content-length') ?? '');

    final body = webResponse.body == null
        ? null
        : toDartStream(
            webResponse.body!,
            onProgress: options.onReceiveProgress,
            total: total,
          );

    if (body == null && options.onReceiveProgress != null) {
      options.onReceiveProgress!(
        const TransferProgress(transferred: 0, total: 0),
      );
    }

    options.onSendProgress?.call(
      const TransferProgress(transferred: 1, total: 1),
    );

    return Response(
      body: body,
      status: webResponse.status,
      statusText: webResponse.statusText,
      headers: responseHeaders,
      redirected: webResponse.redirected,
      url: Uri.tryParse(webResponse.url),
    );
  } catch (error, trace) {
    if (options.signal?.aborted == true) {
      throw OxyCancelledException(reason: options.signal?.reason, trace: trace);
    }

    if (error is OxyException) {
      rethrow;
    }

    throw OxyNetworkException(error.toString(), cause: error, trace: trace);
  }
}

void _bindAbort(AbortController controller, RequestOptions options) {
  final signal = options.signal;
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

String _mapRedirect(RedirectPolicy redirect) {
  return switch (redirect) {
    RedirectPolicy.follow => 'follow',
    RedirectPolicy.manual => 'manual',
    RedirectPolicy.error => 'error',
  };
}
