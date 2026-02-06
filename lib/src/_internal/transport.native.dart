import 'dart:io';
import 'dart:typed_data';

import 'package:ht/ht.dart';

import '../abort.dart';
import '../options.dart';

final HttpClient _client = HttpClient();

Future<Response> fetchTransport(Request request, FetchOptions options) async {
  options.signal?.throwIfAborted();

  try {
    final httpRequest = await _client.openUrl(request.method, request.url);
    _bindAbort(options.signal, httpRequest);

    for (final name in request.headers.names()) {
      final values = request.headers.getAll(name);
      for (final value in values) {
        httpRequest.headers.add(name, value);
      }
    }

    final followRedirects = options.redirect != RedirectPolicy.manual;
    httpRequest.followRedirects = followRedirects;
    httpRequest.maxRedirects = followRedirects ? options.maxRedirects : 0;
    httpRequest.persistentConnection = options.keepAlive;

    final requestBody = request.body;
    if (requestBody != null) {
      await httpRequest.addStream(requestBody);
    }

    final ioResponse = await httpRequest.close();
    final headers = Headers();
    ioResponse.headers.forEach((name, values) {
      for (final value in values) {
        headers.append(name, value);
      }
    });

    final response = Response(
      body: ioResponse.map((chunk) {
        if (chunk is Uint8List) {
          return chunk;
        }

        return Uint8List.fromList(chunk);
      }),
      status: ioResponse.statusCode,
      statusText: ioResponse.reasonPhrase,
      headers: headers,
      redirected: ioResponse.isRedirect,
      url: request.url,
    );

    if (options.redirect == RedirectPolicy.error && response.redirected) {
      throw response;
    }

    return response;
  } catch (error) {
    if (options.signal?.aborted == true) {
      options.signal!.throwIfAborted();
    }
    rethrow;
  }
}

void _bindAbort(AbortSignal? signal, HttpClientRequest request) {
  if (signal == null) {
    return;
  }

  signal.onAbort(() {
    try {
      request.abort(signal.reason);
    } catch (_) {
      // Ignore abort errors from already-completed requests.
    }
  });
}
