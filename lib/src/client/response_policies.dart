import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/body.dart';
import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/events.dart';
import '../policies.dart';

Future<Response> applyResponsePolicies(
  Request request,
  Response response,
  Context context,
) async {
  if (isRedirectBlocked(response, context)) {
    throw StatusError(
      response,
      request: request,
      message: 'Redirect blocked by RedirectPolicy.error.',
    );
  }

  if (!context.statusPolicy.accepts(response)) {
    final preview = await _previewStatusBody(response, context);
    emitEvent(
      context.onEvent,
      RequestEventType.statusFailed,
      request: request,
      attempt: context.attempt,
      response: preview.response,
    );
    throw StatusError(
      preview.response,
      request: request,
      bodyPreview: preview.bodyPreview,
    );
  }

  return response;
}

bool isRedirectBlocked(Response response, Context context) {
  return context.redirectPolicy.mode == RedirectMode.error &&
      isRedirectStatus(response.status);
}

bool isRedirectStatus(int status) {
  return switch (status) {
    301 || 302 || 303 || 307 || 308 => true,
    _ => false,
  };
}

Future<_StatusBodyPreview> _previewStatusBody(
  Response response,
  Context context,
) async {
  final limit = context.clientOptions.errorBodyPreviewLimit;
  final body = response.body;
  if (limit <= 0 || body == null) {
    return _StatusBodyPreview(response: response);
  }

  try {
    final iterator = StreamIterator<Uint8List>(body.open());
    final chunks = <Uint8List>[];
    final builder = BytesBuilder(copy: false);

    while (await iterator.moveNext()) {
      final chunk = iterator.current;
      chunks.add(chunk);
      builder.add(chunk);
      if (builder.length > limit) {
        if (body.replayable) {
          await iterator.cancel();
          return _StatusBodyPreview(response: response);
        }
        return _StatusBodyPreview(
          response: response.copyWith(
            body: ResponseBody.stream(
              _restorePreviewStream(chunks, iterator),
              contentLength: body.contentLength,
            ),
          ),
        );
      }
    }

    final data = builder.takeBytes();
    final next = response.copyWith(body: ResponseBody.fromBytes(data));
    try {
      return _StatusBodyPreview(response: next, bodyPreview: utf8.decode(data));
    } catch (_) {
      return _StatusBodyPreview(response: next);
    }
  } catch (_) {
    return _StatusBodyPreview(response: response);
  }
}

Stream<List<int>> _restorePreviewStream(
  List<Uint8List> chunks,
  StreamIterator<Uint8List> iterator,
) async* {
  try {
    for (final chunk in chunks) {
      yield chunk;
    }
    while (await iterator.moveNext()) {
      yield iterator.current;
    }
  } finally {
    await iterator.cancel();
  }
}

final class _StatusBodyPreview {
  const _StatusBodyPreview({required this.response, this.bodyPreview});

  final Response response;
  final String? bodyPreview;
}
