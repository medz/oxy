import 'dart:async';

import '../core/abort.dart';
import '../core/body.dart';
import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../policies.dart';

AbortSignal linkedSignal(AbortSignal? parent) {
  final signal = AbortSignal();
  if (parent == null) {
    return signal;
  }

  if (parent.aborted) {
    signal.abort(parent.reason);
  } else {
    parent.onAbort(() {
      signal.abort(parent.reason);
    });
  }
  return signal;
}

bool needsInternalSignal(TimeoutPolicy policy) {
  return policy.total != null ||
      policy.send != null ||
      policy.firstByte != null ||
      policy.read != null;
}

Response withResponseTimeouts(
  Response response,
  Request request,
  Context context,
) {
  return withTotalTimeout(
    withReadTimeout(response, request, context),
    request,
    context,
  );
}

Response withReadTimeout(Response response, Request request, Context context) {
  final timeout = context.timeoutPolicy.read;
  final body = response.body;
  if (timeout == null || body == null || body.replayable) {
    return response;
  }

  return response.copyWith(
    body: ResponseBody.stream(
      _readTimeoutStream(body.open(), timeout, request),
      contentLength: body.contentLength,
    ),
  );
}

Response withTotalTimeout(Response response, Request request, Context context) {
  final timeout = context.timeoutPolicy.total;
  final body = response.body;
  if (timeout == null || body == null || body.replayable) {
    return response;
  }

  final deadline = context.createdAt.add(timeout);
  return response.copyWith(
    body: ResponseBody.stream(
      _totalTimeoutStream(
        body.open(),
        timeout,
        deadline,
        request,
        context.signal,
      ),
      contentLength: body.contentLength,
    ),
  );
}

Stream<List<int>> _readTimeoutStream(
  Stream<List<int>> source,
  Duration timeout,
  Request request,
) async* {
  final iterator = StreamIterator<List<int>>(source);
  try {
    while (true) {
      final hasNext = await iterator.moveNext().timeout(
        timeout,
        onTimeout: () {
          final timeoutError = TimeoutError(
            phase: TimeoutPhase.read,
            duration: timeout,
            request: request,
            sent: true,
          );
          throw timeoutError;
        },
      );
      if (!hasNext) {
        break;
      }
      yield iterator.current;
    }
  } finally {
    await iterator.cancel();
  }
}

Stream<List<int>> _totalTimeoutStream(
  Stream<List<int>> source,
  Duration timeout,
  DateTime deadline,
  Request request,
  AbortSignal? signal,
) async* {
  final iterator = StreamIterator<List<int>>(source);
  try {
    while (true) {
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) {
        throw _abortTotalTimeout(timeout, request, signal);
      }

      final hasNext = await iterator.moveNext().timeout(
        remaining,
        onTimeout: () {
          throw _abortTotalTimeout(timeout, request, signal);
        },
      );
      if (!hasNext) {
        break;
      }
      yield iterator.current;
    }
  } finally {
    await iterator.cancel();
  }
}

TimeoutError _abortTotalTimeout(
  Duration timeout,
  Request request,
  AbortSignal? signal,
) {
  final timeoutError = TimeoutError(
    phase: TimeoutPhase.total,
    duration: timeout,
    request: request,
    sent: true,
  );
  signal?.abort(timeoutError);
  return timeoutError;
}
