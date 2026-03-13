import 'package:ht/ht.dart';

Request testRequest(
  Uri uri, {
  String method = 'GET',
  Headers? headers,
  Object? body,
}) {
  return Request(
    RequestInput.uri(uri),
    RequestInit(method: HttpMethod.parse(method), headers: headers, body: body),
  );
}

Headers cloneTestHeaders(Headers headers) => Headers(headers.entries());

Request copyTestRequest(Request request, {Headers? headers, Object? body}) {
  return Request(
    RequestInput.string(request.url),
    RequestInit(
      method: request.method,
      headers: headers ?? cloneTestHeaders(request.headers),
      body: body ?? request.body?.clone(),
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

Response testResponse({
  Object? body,
  int status = 200,
  String? statusText,
  Headers? headers,
}) {
  return Response(
    body,
    ResponseInit(status: status, statusText: statusText, headers: headers),
  );
}

Response textResponse(
  String body, {
  int status = 200,
  String? statusText,
  Headers? headers,
}) {
  final nextHeaders = headers == null ? Headers() : Headers(headers);
  if (!nextHeaders.has('content-type')) {
    nextHeaders.set('content-type', 'text/plain; charset=utf-8');
  }

  return testResponse(
    body: body,
    status: status,
    statusText: statusText,
    headers: nextHeaders,
  );
}
