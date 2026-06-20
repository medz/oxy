/// Cooperative cancellation signal used by requests, retry delays, and bodies.
abstract interface class AbortSignal {
  /// Creates a new, initially active cancellation signal.
  factory AbortSignal() = _AbortSignalImpl;

  /// Whether [abort] has been called.
  bool get aborted;

  /// The reason supplied to [abort], or `null`.
  Object? get reason;

  /// Registers [callback] to run when the signal aborts.
  ///
  /// If the signal is already aborted, [callback] runs immediately.
  void onAbort(void Function() callback);

  /// Throws [reason] if the signal is already aborted.
  void throwIfAborted();

  /// Aborts the signal and notifies registered callbacks.
  void abort([Object? reason]);
}

class _AbortSignalImpl implements AbortSignal {
  bool _aborted = false;
  Object? _reason;
  final List<void Function()> _callbacks = <void Function()>[];

  @override
  bool get aborted => _aborted;

  @override
  Object? get reason => _reason;

  @override
  void abort([Object? reason]) {
    if (_aborted) {
      return;
    }

    _aborted = true;
    _reason = reason;
    final callbacks = List<void Function()>.from(_callbacks);
    _callbacks.clear();

    for (final callback in callbacks) {
      try {
        callback();
      } catch (_) {
        // Cancellation callbacks must not prevent later callbacks from running.
      }
    }
  }

  @override
  void onAbort(void Function() callback) {
    if (_aborted) {
      try {
        callback();
      } catch (_) {
        // Cancellation callbacks must not escape after the signal is settled.
      }
      return;
    }

    _callbacks.add(callback);
  }

  @override
  void throwIfAborted() {
    if (_aborted) {
      throw reason ?? 'aborted';
    }
  }
}
