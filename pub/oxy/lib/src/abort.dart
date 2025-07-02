/// An interface for signaling the abortion of asynchronous operations.
///
/// AbortSignal provides a way to communicate with an asynchronous operation
/// and abort it if needed. This is commonly used with HTTP requests to
/// cancel them before completion.
///
/// Example:
/// ```dart
/// final controller = AbortController();
/// final signal = controller.signal;
///
/// // Set up abort handling
/// signal.onAbort(() {
///   print('Operation was aborted');
/// });
///
/// // Later, abort the operation
/// controller.abort('User cancelled');
/// ```
abstract interface class AbortSignal {
  factory AbortSignal() = _AbortSignalImpl;

  /// Whether the signal has been aborted.
  ///
  /// Returns `true` if [abort] has been called on the associated controller,
  /// `false` otherwise.
  bool get aborted;

  /// The reason for the abortion, if any.
  ///
  /// Returns the reason passed to [abort], or `null` if no reason was provided
  /// or the signal hasn't been aborted yet.
  Object? get reason;

  /// Registers a callback to be called when the signal is aborted.
  ///
  /// If the signal is already aborted when this method is called,
  /// the callback will be executed immediately.
  ///
  /// Example:
  /// ```dart
  /// signal.onAbort(() {
  ///   print('Request cancelled');
  ///   // Clean up resources
  /// });
  /// ```
  void onAbort(void Function() callback);

  /// Throws an exception if the signal has been aborted.
  ///
  /// This method is useful for checking abort status in long-running
  /// operations and immediately terminating execution if needed.
  ///
  /// Throws the abort reason if available, otherwise throws 'aborted'.
  ///
  /// Example:
  /// ```dart
  /// void longRunningOperation(AbortSignal signal) {
  ///   for (int i = 0; i < 1000; i++) {
  ///     signal.throwIfAborted(); // Check if cancelled
  ///     // Do some work...
  ///   }
  /// }
  /// ```
  void throwIfAborted();

  /// Aborts the associated signal with an optional reason.
  void abort([Object? reason]);
}

/// Internal implementation of AbortSignal.
class _AbortSignalImpl implements AbortSignal {
  bool _aborted = false;
  Object? _reason;
  final _callbacks = <void Function()>[];

  @override
  bool get aborted => _aborted;

  @override
  Object? get reason => _reason;

  @override
  void onAbort(void Function() callback) {
    if (aborted) return callback();
    _callbacks.add(callback);
  }

  @override
  void throwIfAborted() {
    if (_aborted) throw _reason ?? 'aborted';
  }

  /// Aborts the signal with an optional reason.
  ///
  /// Once aborted, all registered callbacks will be executed and the signal
  /// will remain in the aborted state. Subsequent calls to this method
  /// will be ignored.
  @override
  void abort([Object? reason]) {
    if (_aborted) return;

    _aborted = true;
    _reason = reason;

    // Execute all callbacks, ignoring any exceptions they might throw
    for (final callback in _callbacks) {
      try {
        callback();
      } catch (_) {
        // Ignore callback exceptions to prevent one callback from
        // affecting others or the abort process itself
      }
    }
    _callbacks.clear();
  }
}
