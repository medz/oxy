import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/errors.dart';
import '../core/headers.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../options.dart';
import '../pipeline/context.dart';
import '../policies.dart';
import 'capability.dart';
import 'transport.dart';

Transport createTransport({bool keepAlive = true}) {
  return NativeTransport(keepAlive: keepAlive);
}

final class NativeTransport implements Transport {
  NativeTransport({bool keepAlive = true}) : _keepAlive = keepAlive;

  final HttpClient _client = HttpClient();
  final bool _keepAlive;
  bool _closed = false;

  @override
  PlatformCapability get capability => PlatformCapability.native;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _client.close(force: true);
  }

  @override
  Future<Response> send(Request request, Context context) async {
    if (_closed) {
      throw NetworkError('Client transport is closed.', request: request);
    }

    context.signal?.throwIfAborted();

    try {
      final openFuture = _client.openUrl(request.method, request.uri);
      final httpRequest = await _withConnectTimeout(
        openFuture,
        context,
        request,
      );

      _bindAbort(context, httpRequest);
      _configureRequest(httpRequest, request, context);
      await _writeBody(httpRequest, request, context);

      final ioResponse = await httpRequest.close();
      final headers = _toHeaders(ioResponse.headers);
      final total = ioResponse.contentLength < 0
          ? null
          : ioResponse.contentLength;
      var transferred = 0;

      final body = ioResponse.map((chunk) {
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        transferred += bytes.length;
        context.onReceiveProgress?.call(
          TransferProgress(transferred: transferred, total: total),
        );
        return bytes;
      });

      if (total == 0) {
        context.onReceiveProgress?.call(
          const TransferProgress(transferred: 0, total: 0),
        );
      }

      final finalUrl = ioResponse.redirects.isEmpty
          ? request.uri
          : ioResponse.redirects.last.location;

      return Response.stream(
        body,
        status: ioResponse.statusCode,
        statusText: ioResponse.reasonPhrase,
        headers: headers,
        url: finalUrl,
        redirected: ioResponse.redirects.isNotEmpty,
        contentLength: total,
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
        retryable: true,
      );
    }
  }

  Future<HttpClientRequest> _withConnectTimeout(
    Future<HttpClientRequest> openFuture,
    Context context,
    Request request,
  ) {
    final timeout = context.timeoutPolicy.connect;
    if (timeout == null) {
      return openFuture;
    }

    return openFuture.timeout(
      timeout,
      onTimeout: () {
        final timeoutError = TimeoutError(
          phase: TimeoutPhase.connect,
          duration: timeout,
          request: request,
        );
        openFuture.then((lateRequest) {
          try {
            lateRequest.abort(timeoutError);
          } catch (_) {}
        }).ignore();
        throw timeoutError;
      },
    );
  }

  void _configureRequest(
    HttpClientRequest httpRequest,
    Request request,
    Context context,
  ) {
    for (final entry in request.headers) {
      httpRequest.headers.add(entry.key, entry.value);
    }

    final body = request.body;
    if (body != null) {
      if (body.contentLength != null &&
          !request.headers.has('content-length')) {
        httpRequest.headers.contentLength = body.contentLength!;
      }
      if (body.contentType != null && !request.headers.has('content-type')) {
        httpRequest.headers.set('content-type', body.contentType!);
      }
    }

    httpRequest.followRedirects =
        context.redirectPolicy.mode == RedirectMode.follow;
    httpRequest.maxRedirects =
        context.redirectPolicy.mode == RedirectMode.follow
        ? context.redirectPolicy.maxRedirects
        : 0;
    httpRequest.persistentConnection = _keepAlive;
  }

  Future<void> _writeBody(
    HttpClientRequest httpRequest,
    Request request,
    Context context,
  ) async {
    final body = request.body;
    if (body == null) {
      context.onSendProgress?.call(
        const TransferProgress(transferred: 0, total: 0),
      );
      return;
    }

    final total = body.contentLength;
    var transferred = 0;

    await for (final chunk in body.open()) {
      context.signal?.throwIfAborted();
      transferred += chunk.length;
      httpRequest.add(chunk);
      context.onSendProgress?.call(
        TransferProgress(transferred: transferred, total: total),
      );
    }
  }

  void _bindAbort(Context context, HttpClientRequest request) {
    final signal = context.signal;
    if (signal == null) {
      return;
    }

    signal.onAbort(() {
      try {
        request.abort(signal.reason);
      } catch (_) {}
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
}
