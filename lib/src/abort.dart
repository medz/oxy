import 'package:meta/meta.dart';

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
  const AbortSignal();

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

  @internal
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

/// A controller for creating and managing AbortSignal instances.
///
/// AbortController provides a way to abort one or more asynchronous operations
/// through its associated AbortSignal. This is commonly used to implement
/// cancellation for HTTP requests, timers, and other async operations.
///
/// Example usage:
/// ```dart
/// // Create a controller
/// final controller = AbortController();
///
/// // Pass the signal to an async operation
/// try {
///   final response = await httpClient.get(
///     'https://api.example.com/data',
///     signal: controller.signal,
///   );
///   print('Request completed: ${response.body}');
/// } catch (e) {
///   print('Request failed or was aborted: $e');
/// }
///
/// // Later, abort the operation
/// controller.abort('User requested cancellation');
/// ```
///
/// Example with timeout:
/// ```dart
/// final controller = AbortController();
///
/// // Set up automatic abortion after 5 seconds
/// Timer(Duration(seconds: 5), () {
///   controller.abort('Request timeout');
/// });
///
/// // Use the signal with your async operation
/// await someAsyncOperation(controller.signal);
/// ```
class AbortController {
  /// Creates a new AbortController with a fresh AbortSignal.
  AbortController() : _signal = _AbortSignalImpl();

  final _AbortSignalImpl _signal;

  /// The AbortSignal associated with this controller.
  ///
  /// This signal can be passed to asynchronous operations to allow them
  /// to be cancelled via this controller.
  AbortSignal get signal => _signal;

  /// Aborts the associated signal with an optional reason.
  ///
  /// Once called, the signal's [AbortSignal.aborted] property will be `true`
  /// and all registered abort callbacks will be executed.
  ///
  /// The [reason] parameter allows you to specify why the operation was
  /// aborted, which can be useful for debugging or providing user feedback.
  ///
  /// Example:
  /// ```dart
  /// controller.abort(); // Abort without reason
  /// controller.abort('User cancelled'); // Abort with reason
  /// controller.abort(TimeoutException('Request took too long'));
  /// ```
  void abort([Object? reason]) => _signal.abort(reason);
}
