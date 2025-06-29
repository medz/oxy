class _EventListener {
  const _EventListener({
    this.capture = false,
    this.once = false,
    this.passive = false,
    this.signal,
    required this.callback,
    required this.type,
  });

  final String type;
  final bool capture;
  final bool once;
  final bool passive;
  final AbortSignal? signal;
  final void Function(Event event) callback;
}

class Event {
  Event({
    required this.type,
    this.bubbles = false,
    this.cancelable = false,
    this.composed = false,
    this.currentTarget,
    this.isTrusted = false,
    this.target,
    int? timeStamp,
  }) : timeStamp = timeStamp ?? DateTime.now().millisecondsSinceEpoch;

  final bool bubbles;
  final bool cancelable;
  final bool composed;
  EventTarget? currentTarget;
  bool _defaultPrevented = false;
  final bool isTrusted;
  EventTarget? target;
  final int timeStamp;
  final String type;

  bool _immediatePropagationStopped = false;

  bool get defaultPrevented => _defaultPrevented;

  void preventDefault() {
    if (cancelable) {
      _defaultPrevented = true;
    }
  }

  void stopImmediatePropagation() {
    _immediatePropagationStopped = true;
  }

  // For fetch API, stopPropagation is equivalent to stopImmediatePropagation
  // since there's no propagation chain
  void stopPropagation() {
    _immediatePropagationStopped = true;
  }
}

class EventTarget {
  final _listeners = <_EventListener>[];

  void addEventListener(
    String type,
    void Function(Event event) listener, {
    bool capture = false,
    bool once = false,
    bool passive = false,
    AbortSignal? signal,
  }) {
    final eventListener = _EventListener(
      type: type,
      callback: listener,
      capture: capture,
      once: once,
      passive: passive,
      signal: signal,
    );
    _listeners.add(eventListener);
  }

  void removeEventListener(
    String type,
    void Function(Event event) listener, {
    bool capture = false,
  }) {
    _listeners.removeWhere((eventListener) {
      return eventListener.type == type &&
          eventListener.callback == listener &&
          eventListener.capture == capture;
    });
  }

  bool dispatchEvent(Event event) {
    // Set event target and currentTarget
    event.target ??= this;
    event.currentTarget = this;

    // Collect listeners to call and remove
    final listenersToCall = <_EventListener>[];
    final listenersToRemove = <_EventListener>[];

    for (final listener in _listeners) {
      if (listener.type == event.type) {
        // Check if AbortSignal is aborted
        if (listener.signal?.aborted == true) {
          listenersToRemove.add(listener);
          continue;
        }

        listenersToCall.add(listener);
      }
    }

    // Remove aborted listeners
    for (final listener in listenersToRemove) {
      _listeners.remove(listener);
    }

    // Call listeners
    for (final listener in listenersToCall) {
      if (event._immediatePropagationStopped) {
        break;
      }

      listener.callback(event);

      // Remove once listeners
      if (listener.once) {
        _listeners.remove(listener);
      }
    }

    return !event.defaultPrevented;
  }
}

class AbortSignal extends EventTarget {
  AbortSignal() : _aborted = false;

  factory AbortSignal.abort([dynamic reason]) {
    return AbortSignal().._abort(reason);
  }

  factory AbortSignal.timeout(int milliseconds) {
    final signal = AbortSignal();
    Future.delayed(Duration(milliseconds: milliseconds), () {
      signal._abort('TimeoutError');
    });

    return signal;
  }

  bool _aborted;
  dynamic _reason;

  void Function(Event event)? onabort;
  bool get aborted => _aborted;
  dynamic get reason => _reason;

  void throwIfAborted() {
    if (_aborted) {
      throw _reason ?? 'AbortError';
    }
  }

  void _abort([dynamic reason]) {
    if (_aborted) return;

    _aborted = true;
    _reason = reason;

    final event = Event(type: 'abort');
    onabort?.call(event);
    dispatchEvent(event);
  }
}

class AbortController {
  AbortController() : _signal = AbortSignal();

  final AbortSignal _signal;

  AbortSignal get signal => _signal;

  void abort([dynamic reason]) => signal._abort(reason);
}
