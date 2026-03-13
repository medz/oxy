import 'package:ht/ht.dart';

Headers cloneHeaders(Headers headers) => Headers(headers.entries());

Request copyRequest(
  Request request, {
  Uri? url,
  HttpMethod? method,
  Headers? headers,
  Object? body = _bodySentinel,
}) {
  final hasBody = !identical(body, _bodySentinel);

  return Request(
    RequestInput.string((url ?? Uri.parse(request.url)).toString()),
    RequestInit(
      method: method ?? request.method,
      headers: headers ?? cloneHeaders(request.headers),
      body: hasBody ? body : request.body?.clone(),
      referrer: request.referrer,
      referrerPolicy: request.referrerPolicy,
      mode: request.mode,
      credentials: request.credentials,
      cache: request.cache,
      redirect: request.redirect,
      integrity: request.integrity,
      keepalive: request.keepalive,
      duplex: request.duplex,
    ),
  );
}

const Object _bodySentinel = Object();
