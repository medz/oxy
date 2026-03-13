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
