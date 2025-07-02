import 'dart:async';

(Stream<T>, Stream<T>) teeStreamToTwoStreams<T>(Stream<T> source) {
  if (source.isBroadcast) {
    return (source, source);
  }

  final c1 = StreamController<T>();
  final c2 = StreamController<T>();

  StreamSubscription<T>? subscription;
  int subsCount = 0;

  c1.onListen = c2.onListen = () {
    subsCount++;
    if (subsCount > 1) return;
    subscription ??= source.listen(
      (event) {
        if (!c1.isClosed) c1.add(event);
        if (!c2.isClosed) c2.add(event);
      },
      onError: (err, stackTrace) {
        if (!c1.isClosed) c1.addError(err, stackTrace);
        if (!c2.isClosed) c2.addError(err, stackTrace);
      },
      onDone: () {
        if (!c1.isClosed) c1.close();
        if (!c2.isClosed) c2.close();
      },
    );
  };
  c1.onCancel = c2.onCancel = () {
    subsCount--;
    if (subsCount != 0) return;
    subscription?.cancel();
  };

  return (c1.stream, c2.stream);
}
