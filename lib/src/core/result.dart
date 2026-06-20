/// A no-throw result for request helpers.
///
/// Use [Result.capture], `Client.sendResult`, `Client.requestResult`, or
/// `fetchResult` when an HTTP failure should be handled as a value instead of
/// an exception.
sealed class Result<T> {
  const Result();

  /// Runs [action] and captures either a [Success] or [Failure].
  static Future<Result<T>> capture<T>(Future<T> Function() action) async {
    try {
      return Success<T>(await action());
    } catch (error, trace) {
      return Failure<T>(error, trace);
    }
  }

  /// Whether this result contains a value.
  bool get isSuccess;

  /// Whether this result contains an error.
  bool get isFailure => !isSuccess;

  /// The value for [Success], otherwise `null`.
  T? get value;

  /// The error for [Failure], otherwise `null`.
  Object? get error;

  /// The stack trace for [Failure], otherwise `null`.
  StackTrace? get trace;

  /// Folds this result into one value.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object error, StackTrace trace) onFailure,
  }) {
    return switch (this) {
      Success<T>(:final data) => onSuccess(data),
      Failure<T>(:final cause, :final stack) => onFailure(cause, stack),
    };
  }

  /// Maps a successful value while preserving failures.
  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T>(:final data) => _mapSuccess(data, transform),
      Failure<T>(:final cause, :final stack) => Failure<R>(cause, stack),
    };
  }

  /// Returns the value or rethrows the captured error with its stack trace.
  T getOrThrow() {
    return switch (this) {
      Success<T>(:final data) => data,
      Failure<T>(:final cause, :final stack) => Error.throwWithStackTrace(
        cause,
        stack,
      ),
    };
  }

  static Result<R> _mapSuccess<T, R>(T value, R Function(T value) transform) {
    try {
      return Success<R>(transform(value));
    } catch (error, trace) {
      return Failure<R>(error, trace);
    }
  }
}

/// A successful [Result].
final class Success<T> extends Result<T> {
  const Success(this.data);

  /// The captured value.
  final T data;

  @override
  bool get isSuccess => true;

  @override
  T get value => data;

  @override
  Object? get error => null;

  @override
  StackTrace? get trace => null;
}

/// A failed [Result].
final class Failure<T> extends Result<T> {
  const Failure(this.cause, this.stack);

  /// The captured error.
  final Object cause;

  /// The captured stack trace.
  final StackTrace stack;

  @override
  bool get isSuccess => false;

  @override
  T? get value => null;

  @override
  Object get error => cause;

  @override
  StackTrace get trace => stack;
}
