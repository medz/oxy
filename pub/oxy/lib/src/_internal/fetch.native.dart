import 'dart:io';
import 'dart:typed_data';

import '../adapter_request.dart';
import '../body.dart';
import '../request_common.dart';
import '../response.dart';

final client = HttpClient();

Future<Response> fetch(Uri url, AdapterRequest request) async {
  final httpRequest = await client.openUrl(request.method, url);

  request.signal.onAbort(() => httpRequest.abort(request.signal.reason));

  for (final (name, value) in request.headers.entries()) {
    httpRequest.headers.add(name, value);
  }

  httpRequest.followRedirects = request.redirect == RequestRedirect.follow;
  httpRequest.persistentConnection = request.keepalive;
  httpRequest.maxRedirects = request.redirect == RequestRedirect.manual ? 0 : 5;

  if (request.method != "GET") {
    await httpRequest.addStream(request.body);
  }

  final httpResponse = await httpRequest.close();
  final body = Body(
    httpResponse.map((event) {
      if (event is Uint8List) return event;
      return Uint8List.fromList(event);
    }),
  );
  body.headers.set('content-type', httpResponse.headers.contentType.toString());

  final response = Response(
    status: httpResponse.statusCode,
    statusText: httpResponse.reasonPhrase,
    redirected: httpResponse.isRedirect,
    url: url.toString(),
    body: body,
  );
  httpResponse.headers.forEach((name, values) {
    for (final value in values) {
      response.headers.append(name, value);
    }
  });

  if (response.redirected && request.redirect == RequestRedirect.error) {
    throw response;
  }

  return response;
}
