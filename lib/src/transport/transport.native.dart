import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/errors.dart';
import '../core/headers.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../options.dart';
import '../pipeline/context.dart';
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
      final httpRequest = await _withConnectAbort(
        _withConnectTimeout(openFuture, context, request),
        openFuture,
        context,
        request,
      );

      _bindAbort(context, httpRequest);
      _configureRequest(httpRequest, request, context);
      await _writeBody(httpRequest, request, context);
      final ioResponse = await _withFirstByteTimeout(
        httpRequest.close(),
        httpRequest,
        request,
        context,
      );
      final headers = _toHeaders(ioResponse.headers);
      final total = ioResponse.contentLength < 0
          ? null
          : ioResponse.contentLength;
      final body = _responseBody(ioResponse, request, context, total);

      if (total == 0) {
        context.onReceiveProgress?.call(
          const TransferProgress(transferred: 0, total: 0),
        );
      }

      return Response.stream(
        body,
        status: ioResponse.statusCode,
        statusText: ioResponse.reasonPhrase,
        headers: headers,
        url: request.uri,
        redirected: false,
        contentLength: total,
      );
    } catch (error, trace) {
      if (context.signal?.aborted == true) {
        if (context.signal?.reason case final TimeoutError timeoutError) {
          throw timeoutError;
        }
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
        _abortLate(openFuture, timeoutError);
        throw timeoutError;
      },
    );
  }

  Future<HttpClientRequest> _withConnectAbort(
    Future<HttpClientRequest> connectFuture,
    Future<HttpClientRequest> openFuture,
    Context context,
    Request request,
  ) {
    final signal = context.signal;
    if (signal == null) {
      return connectFuture;
    }

    if (signal.aborted) {
      _abortLate(openFuture, signal.reason);
      return Future<HttpClientRequest>.error(
        CancelError(reason: signal.reason, request: request),
      );
    }

    final completer = Completer<HttpClientRequest>();
    signal.onAbort(() {
      _abortLate(openFuture, signal.reason);
      if (!completer.isCompleted) {
        completer.completeError(
          CancelError(reason: signal.reason, request: request),
        );
      }
    });

    connectFuture.then(
      (httpRequest) {
        if (completer.isCompleted) {
          try {
            httpRequest.abort(signal.reason);
          } catch (_) {}
          return;
        }
        completer.complete(httpRequest);
      },
      onError: (Object error, StackTrace trace) {
        if (!completer.isCompleted) {
          completer.completeError(error, trace);
        }
      },
    );
    return completer.future;
  }

  void _abortLate(Future<HttpClientRequest> openFuture, Object? reason) {
    openFuture.then((lateRequest) {
      try {
        lateRequest.abort(reason);
      } catch (_) {}
    }).ignore();
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

    httpRequest.followRedirects = false;
    httpRequest.maxRedirects = 0;
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

    final chunks = StreamIterator<Uint8List>(body.open());
    Future<void>? cancelFuture;
    Future<void> cancelChunks() {
      return cancelFuture ??= chunks.cancel();
    }

    final abortSignal = context.signal;
    final abortCompleter = Completer<void>();
    if (abortSignal != null) {
      if (abortSignal.aborted) {
        unawaited(cancelChunks());
        throw CancelError(reason: abortSignal.reason, request: request);
      }
      abortSignal.onAbort(() {
        if (!abortCompleter.isCompleted) {
          abortCompleter.complete();
        }
        unawaited(cancelChunks());
      });
    }

    Future<bool> moveNextChunk() {
      final moveNext = chunks.moveNext();
      if (abortSignal == null) {
        return moveNext;
      }
      return Future.any<bool>([
        moveNext,
        abortCompleter.future.then((_) {
          throw CancelError(reason: abortSignal.reason, request: request);
        }),
      ]);
    }

    TimeoutError? sendTimeoutError;
    final sendTimeout = context.timeoutPolicy.send;
    final sendTimer = sendTimeout == null
        ? null
        : Timer(sendTimeout, () {
            final timeoutError = TimeoutError(
              phase: TimeoutPhase.send,
              duration: sendTimeout,
              request: request,
              sent: true,
            );
            sendTimeoutError = timeoutError;
            context.signal?.abort(timeoutError);
            try {
              httpRequest.abort(timeoutError);
            } catch (_) {}
            unawaited(cancelChunks());
          });

    try {
      while (await moveNextChunk()) {
        final timeoutError = sendTimeoutError;
        if (timeoutError != null) {
          throw timeoutError;
        }
        context.signal?.throwIfAborted();
        final chunk = chunks.current;
        transferred += chunk.length;
        httpRequest.add(chunk);
        context.onSendProgress?.call(
          TransferProgress(transferred: transferred, total: total),
        );
      }
      final timeoutError = sendTimeoutError;
      if (timeoutError != null) {
        throw timeoutError;
      }
      await httpRequest.flush();
    } catch (_) {
      final timeoutError = sendTimeoutError;
      if (timeoutError != null) {
        throw timeoutError;
      }
      rethrow;
    } finally {
      sendTimer?.cancel();
      await cancelChunks();
    }
  }

  Future<HttpClientResponse> _withFirstByteTimeout(
    Future<HttpClientResponse> responseFuture,
    HttpClientRequest httpRequest,
    Request request,
    Context context,
  ) {
    final timeout = context.timeoutPolicy.firstByte;
    if (timeout == null) {
      return responseFuture;
    }

    return responseFuture.timeout(
      timeout,
      onTimeout: () {
        final timeoutError = TimeoutError(
          phase: TimeoutPhase.firstByte,
          duration: timeout,
          request: request,
          sent: true,
        );
        try {
          httpRequest.abort(timeoutError);
        } catch (_) {}
        throw timeoutError;
      },
    );
  }

  Stream<Uint8List> _responseBody(
    HttpClientResponse response,
    Request request,
    Context context,
    int? total,
  ) async* {
    var transferred = 0;
    try {
      await for (final chunk in response) {
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        transferred += bytes.length;
        context.onReceiveProgress?.call(
          TransferProgress(transferred: transferred, total: total),
        );
        yield bytes;
      }
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
        sent: true,
        retryable: true,
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
