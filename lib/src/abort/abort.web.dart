import 'dart:js_interop';

extension type _EventInit._(JSObject _) {
  external factory _EventInit({bool bubbles, bool cancelable, bool composed});
}

@JS("Event")
extension type Event._(JSObject _) implements JSObject {
  @JS("constructor")
  external factory Event._constructor(String type, [_EventInit? init]);

  factory Event(
    String type, {
    required bool bubbles,
    required bool cancelable,
    required bool composed,
  }) {
    final init = _EventInit(
      bubbles: bubbles,
      cancelable: cancelable,
      composed: composed,
    );

    return Event._constructor(type, init);
  }

  external bool get bubbles;
  external bool get cancelable;
  external bool get composed;
  external EventTarget? get currentTarget;
  external bool get defaultPrevented;
  external int get eventPhase;
  external bool get isTrusted;
  external EventTarget? get target;
  external int get timeStamp;
  external String get type;

  external JSArray<EventTarget> _composedPath();
  List<EventTarget> composedPath() => _composedPath().toDart;

  external void preventDefault();
  external void stopImmediatePropagation();
  external void stopPropagation();
}

extension type _EventListenerOptions._(JSObject _) {
  external factory _EventListenerOptions({bool? capture});
}

extension type _AddEventListenerOptions._(JSObject _)
    implements _EventListenerOptions {
  external factory _AddEventListenerOptions({
    bool capture,
    bool once,
    bool passive,
    AbortSignal? signal,
  });
}

@JS("EventTarget")
extension type EventTarget._(JSObject _) implements JSObject {
  external factory EventTarget();

  @JS("addEventListener")
  external void _addEventListener(
    String type,
    JSFunction listener, [
    _AddEventListenerOptions options,
  ]);

  void addEventListener(
    String type,
    void Function(Event event) listener, {
    bool capture = false,
    bool once = false,
    bool passive = false,
    AbortSignal? signal,
  }) {
    final options = _AddEventListenerOptions(
      capture: capture,
      once: once,
      passive: passive,
      signal: signal,
    );
    _addEventListener(type, listener.toJS, options);
  }

  @JS("removeEventListener")
  external void _removeEventListener(
    String type,
    JSFunction listener, [
    _EventListenerOptions options,
  ]);

  void removeEventListener(
    String type,
    void Function(Event event) listener, {
    bool capture = false,
  }) {
    final options = _EventListenerOptions(capture: capture);
    _removeEventListener(type, listener.toJS, options);
  }

  external bool dispatchEvent(Event event);
}

@JS("AbortSignal")
extension type AbortSignal._(JSObject _) implements EventTarget {
  external factory AbortSignal();

  @JS("abort")
  external static AbortSignal _abort([JSAny? reason]);
  factory AbortSignal.abort([Object? reason]) =>
      AbortSignal._abort(reason?.jsify());

  @JS("any")
  external static AbortSignal _any(JSArray<AbortSignal> _);
  factory AbortSignal.any(Iterable<AbortSignal> signals) =>
      AbortSignal._any(signals.toList().toJS);

  external static AbortSignal timeout(int milliseconds);

  external bool get aborted;

  @JS("reason")
  external JSAny? get _reason;
  Object? get reason => _reason?.dartify();

  @JS("onabort")
  external JSFunction? _onabort;
  void Function(Event event)? get onabort {
    if (_onabort == null) return null;
    return (event) {
      _onabort!.callAsFunction(event);
    };
  }

  set onabort(void Function(Event event)? callback) {
    _onabort = callback?.toJS;
  }

  external void throwIfAborted();
}

@JS("AbortController")
extension type AbortController._(JSObject _) implements JSObject {
  external factory AbortController();

  @JS("abort")
  external void _abort([JSAny? reason]);
  void abort([Object? reason]) => _abort(reason?.jsify());

  external AbortSignal get signal;
}
