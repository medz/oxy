import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../adapter_request.dart' as oxy;
import '../formdata.dart' as oxy;
import '../headers.dart' as oxy;
import '../request_common.dart' as oxy;
import '../response.dart' as oxy;
import 'web_stream_utils.dart';

extension type IteratorReturnResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSObject? get value;
}

extension type ArrayIterator._(JSObject _) implements JSObject {
  external IteratorReturnResult next();
}

@JS('Array')
extension type JSArrayStatic<T>._(JSAny _) {
  external static bool isArray(JSAny _);
}

@JS("Headers")
extension type Headers._(JSObject _) implements JSAny {
  external factory Headers();
  external void append(String name, String value);
  external ArrayIterator entries();
}

@JS("AbortSignal")
extension type AbortSignal._(JSObject _) implements JSObject {
  external JSFunction? onabort;
}

extension type RequestInit._(JSObject _) implements JSObject {
  external factory RequestInit({
    ReadableStream? body,
    String? cache,
    String? credentials,
    Headers? headers,
    String? integrity,
    bool? keepalive,
    String? method,
    String? mode,
    String? priority,
    String? redirect,
    String? referrer,
    String? referrerPolicy,
    AbortSignal? signal,
  });

  external ReadableStream? body;
}

@JS("Request")
extension type Request._(JSObject _) implements JSObject {
  external factory Request(String url, RequestInit init);
  external AbortSignal get signal;
}

extension type FormData._(JSObject _) implements JSObject {
  external ArrayIterator entries();
}

@JS("Response")
extension type Response._(JSObject _) implements JSObject {
  external bool get bodyUsed;
  external bool get ok;
  external String get url;
  external int get status;
  external String get statusText;
  external String get type;
  external bool get redirected;
  external Headers get headers;

  external Response clone();
  external JSPromise<JSString> text();
  external JSPromise<JSUint8Array> bytes();
  external JSPromise<FormData> formData();
}

@JS("File")
extension type File._(JSObject _) implements JSObject {
  external String get name;
  external int get size;
  external String get type;
  external ReadableStream stream();
}

@JS("fetch")
@staticInterop
@anonymous
external JSPromise<Response> webFetch(Request request);

class ResponseProxy implements oxy.Response {
  ResponseProxy(this.response);

  final Response response;
  oxy.Headers? _headers;

  @override
  Stream<Uint8List> get body => throw UnimplementedError();

  @override
  bool get bodyUsed => response.bodyUsed;

  @override
  Future<Uint8List> bytes() {
    return response.bytes().toDart.then((value) => value.toDart);
  }

  @override
  oxy.Response clone() {
    return ResponseProxy(response.clone());
  }

  @override
  Future<oxy.FormData> formData() async {
    final form = oxy.FormData();
    final iterator = await response.formData().toDart.then(
      (value) => value.entries(),
    );
    while (true) {
      final result = iterator.next();
      if (result.done) break;
      if (result.value == null ||
          result.value.isUndefinedOrNull ||
          JSArrayStatic.isArray(result.value!)) {
        continue;
      }
      final [name, value] = (result.value as JSArray<JSAny>).toDart;
      if (value.typeofEquals("string")) {
        form.append(
          (name as JSString).toDart,
          oxy.FormDataTextEntry((value as JSString).toDart),
        );
      } else if (value.instanceOfString("File")) {
        final file = value as File;
        final entry = oxy.FormDataFileEntry(
          toDartStream(file.stream()),
          filename: file.name,
          contentType: file.type,
          size: file.size,
        );
        form.append((name as JSString).toDart, entry);
      }
    }

    return form;
  }

  @override
  oxy.Headers get headers {
    if (_headers != null) return _headers!;
    final headers = _headers = oxy.Headers();
    final iterator = response.headers.entries();
    while (true) {
      final result = iterator.next();
      if (result.done) break;
      if (result.value == null ||
          result.value.isUndefinedOrNull ||
          JSArrayStatic.isArray(result.value!)) {
        continue;
      }
      final [name, value] = (result.value as JSArray<JSString>).toDart;
      headers.append(name.toDart, value.toDart);
    }

    return headers;
  }

  @override
  Future json() async {
    return jsonDecode(await text());
  }

  @override
  bool get ok => response.ok;

  @override
  bool get redirected => response.redirected;

  @override
  int get status => response.status;

  @override
  String get statusText => response.statusText;

  @override
  Future<String> text() async {
    return response.text().toDart.then((value) => value.toDart);
  }

  @override
  oxy.ResponseType get type => oxy.ResponseType.lookup(response.type);

  @override
  String get url => response.url;
}

Future<oxy.Response> fetch(Uri url, oxy.AdapterRequest request) async {
  final headers = Headers();
  for (final (name, value) in request.headers.entries()) {
    headers.append(name, value);
  }

  final init = RequestInit(
    method: request.method,
    cache: request.cache.toString(),
    credentials: request.credentials.toString(),
    headers: headers,
    integrity: request.integrity,
    keepalive: request.keepalive,
    mode: request.mode.toString(),
    priority: request.priority.toString(),
    redirect: request.redirect.toString(),
    referrer: request.referrer.toString(),
    referrerPolicy: request.referrerPolicy.toString(),
  );
  if (request.method != "GET") {
    init.body = toWebReadableStream(request.body);
  }

  final webRequest = Request(url.toString(), init);
  webRequest.signal.onabort = () {
    request.signal.abort();
  }.toJS;
  final webResponse = await webFetch(webRequest).toDart;
  final response = ResponseProxy(webResponse);

  if (webResponse.status == 0 ||
      (request.redirect == oxy.RequestRedirect.error && response.redirected)) {
    throw response;
  }
  return response;
}
