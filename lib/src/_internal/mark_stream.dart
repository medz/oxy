import 'dart:async';

class MarkStream<T> extends Stream<T> {
  MarkStream(this._source);

  final Stream<T> _source;
  bool _used = false;

  bool get used => _used;

  @override
  bool get isBroadcast => _source.isBroadcast;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (!isBroadcast) _used = true;
    return _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
