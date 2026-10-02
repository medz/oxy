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
      _readTimeoutStream(body.open(), timeout, request, context.signal),
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
  AbortSignal? signal,
) => _timeoutStream(source, timeout, TimeoutPhase.read, request, signal);

Stream<List<int>> _totalTimeoutStream(
  Stream<List<int>> source,
  Duration timeout,
  DateTime deadline,
  Request request,
  AbortSignal? signal,
) => _timeoutStream(
  source,
  timeout,
  TimeoutPhase.total,
  request,
  signal,
  deadline: deadline,
);

Stream<List<int>> _timeoutStream(
  Stream<List<int>> source,
  Duration timeout,
  TimeoutPhase phase,
  Request request,
  AbortSignal? signal, {
  DateTime? deadline,
}) {
  late final StreamController<List<int>> controller;
  late final StreamSubscription<List<int>> subscription;
  Timer? timer;
  var ended = false;
  Future<void>? cancellation;

  Future<void> cancelSource() => cancellation ??= subscription.cancel();

  void expire() {
    if (ended) return;
    ended = true;
    final error = TimeoutError(
      phase: phase,
      duration: timeout,
      request: request,
      sent: true,
    );
    controller.addError(error);
    signal?.abort(error);
    unawaited(controller.close());
    unawaited(cancelSource().catchError((Object _) {}));
  }

  void startTimer() {
    timer?.cancel();
    final remaining = deadline?.difference(DateTime.now().toUtc()) ?? timeout;
    if (deadline != null && remaining <= Duration.zero) {
      expire();
    } else {
      timer = Timer(remaining, expire);
    }
  }

  controller = StreamController<List<int>>(
    onListen: () {
      subscription = source.listen(
        (chunk) {
          if (ended) return;
          controller.add(chunk);
          if (deadline == null) startTimer();
        },
        onError: (Object error, StackTrace trace) {
          if (ended) return;
          ended = true;
          timer?.cancel();
          controller.addError(error, trace);
          unawaited(controller.close());
          unawaited(cancelSource().catchError((Object _) {}));
        },
        onDone: () {
          ended = true;
          timer?.cancel();
          unawaited(controller.close());
        },
      );
      startTimer();
    },
    onPause: () {
      if (deadline == null) timer?.cancel();
      subscription.pause();
    },
    onResume: () {
      subscription.resume();
      if (deadline == null && !ended) startTimer();
    },
    onCancel: () {
      ended = true;
      timer?.cancel();
      return cancelSource();
    },
  );
  return controller.stream;
}
