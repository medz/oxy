sealed class Result<T> {
  const Result();

  static Future<Result<T>> capture<T>(Future<T> Function() action) async {
    try {
      return Success<T>(await action());
    } catch (error, trace) {
      return Failure<T>(error, trace);
    }
  }

  bool get isSuccess;
  bool get isFailure => !isSuccess;
  T? get value;
  Object? get error;
  StackTrace? get trace;

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object error, StackTrace trace) onFailure,
  }) {
    return switch (this) {
      Success<T>(:final data) => onSuccess(data),
      Failure<T>(:final cause, :final stack) => onFailure(cause, stack),
    };
  }

  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T>(:final data) => _mapSuccess(data, transform),
      Failure<T>(:final cause, :final stack) => Failure<R>(cause, stack),
    };
  }

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

final class Success<T> extends Result<T> {
  const Success(this.data);

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

final class Failure<T> extends Result<T> {
  const Failure(this.cause, this.stack);

  final Object cause;
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
