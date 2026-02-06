import 'dart:io';
import 'dart:typed_data';

import 'package:ht/ht.dart';

import '../abort.dart';
import '../errors.dart';
import '../options.dart';

final HttpClient _client = HttpClient();

Future<Response> fetchTransport(Request request, RequestOptions options) async {
  options.signal?.throwIfAborted();

  try {
    final openFuture = _client.openUrl(request.method, request.url);

    final connectTimeout = options.connectTimeout;
    final httpRequest = connectTimeout == null
        ? await openFuture
        : await openFuture.timeout(
            connectTimeout,
            onTimeout: () {
              throw OxyTimeoutException(
                phase: TimeoutPhase.connect,
                duration: connectTimeout,
              );
            },
          );

    _bindAbort(options.signal, httpRequest);

    for (final name in request.headers.names()) {
      final values = request.headers.getAll(name);
      for (final value in values) {
        httpRequest.headers.add(name, value);
      }
    }

    final followRedirects = options.redirectPolicy == RedirectPolicy.follow;
    httpRequest.followRedirects = followRedirects;
    httpRequest.maxRedirects = followRedirects
        ? (options.maxRedirects ?? 5)
        : 0;
    httpRequest.persistentConnection = options.keepAlive ?? false;

    final body = request.body;
    if (body != null) {
      final total = int.tryParse(request.headers.get('content-length') ?? '');
      var transferred = 0;
      await for (final chunk in body) {
        options.signal?.throwIfAborted();
        transferred += chunk.length;
        httpRequest.add(chunk);
        options.onSendProgress?.call(
          TransferProgress(transferred: transferred, total: total),
        );
      }
    } else if (options.onSendProgress != null) {
      options.onSendProgress!(const TransferProgress(transferred: 0, total: 0));
    }

    final ioResponse = await httpRequest.close();
    final headers = Headers();
    ioResponse.headers.forEach((name, values) {
      for (final value in values) {
        headers.append(name, value);
      }
    });

    final total = ioResponse.contentLength < 0
        ? null
        : ioResponse.contentLength;
    var transferred = 0;
    final bodyStream = ioResponse.map((chunk) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      transferred += bytes.length;
      options.onReceiveProgress?.call(
        TransferProgress(transferred: transferred, total: total),
      );
      return bytes;
    });

    if (options.onReceiveProgress != null && ioResponse.contentLength == 0) {
      options.onReceiveProgress!(
        const TransferProgress(transferred: 0, total: 0),
      );
    }

    return Response(
      body: bodyStream,
      status: ioResponse.statusCode,
      statusText: ioResponse.reasonPhrase,
      headers: headers,
      redirected: ioResponse.redirects.isNotEmpty,
      url: request.url,
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
