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
    final headers = _toHeaders(ioResponse.headers);

    if (options.redirectPolicy == RedirectPolicy.error &&
        _isRedirectStatus(ioResponse.statusCode)) {
      try {
        // Release the underlying socket before throwing.
        await ioResponse.drain<void>();
      } catch (_) {
        // Ignore drain errors and still surface redirect policy failure.
      }

      throw OxyHttpException(
        Response(
          status: ioResponse.statusCode,
          statusText: ioResponse.reasonPhrase,
          headers: headers,
          url: request.url,
        ),
        message: 'Redirect blocked by RedirectPolicy.error',
      );
    }

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

Headers _toHeaders(HttpHeaders ioHeaders) {
  final headers = Headers();
  ioHeaders.forEach((name, values) {
    for (final value in values) {
      headers.append(name, value);
    }
  });
  return headers;
}

bool _isRedirectStatus(int statusCode) {
  switch (statusCode) {
    case HttpStatus.multipleChoices:
    case HttpStatus.movedPermanently:
    case HttpStatus.found:
    case HttpStatus.seeOther:
    case 305:
    case HttpStatus.temporaryRedirect:
    case HttpStatus.permanentRedirect:
      return true;
    default:
      return false;
  }
}
