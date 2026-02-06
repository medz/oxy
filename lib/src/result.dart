sealed class OxyResult<T> {
  const OxyResult();

  bool get isSuccess;
  bool get isFailure => !isSuccess;

  T? get value;
  Object? get error;
  StackTrace? get trace;

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object error, StackTrace trace) onFailure,
  }) {
    if (this is OxySuccess<T>) {
      final success = this as OxySuccess<T>;
      return onSuccess(success.data);
    }

    final failure = this as OxyFailure<T>;
    return onFailure(failure.cause, failure.stack);
  }

  OxyResult<R> map<R>(R Function(T value) transform) {
    if (this is OxySuccess<T>) {
      final success = this as OxySuccess<T>;
      try {
        return OxySuccess<R>(transform(success.data));
      } catch (error, trace) {
        return OxyFailure<R>(error, trace);
      }
    }

    final failure = this as OxyFailure<T>;
    return OxyFailure<R>(failure.cause, failure.stack);
  }

  T getOrThrow() {
    if (this is OxySuccess<T>) {
      return (this as OxySuccess<T>).data;
    }

    final failure = this as OxyFailure<T>;
    Error.throwWithStackTrace(failure.cause, failure.stack);
  }
}

class OxySuccess<T> extends OxyResult<T> {
  const OxySuccess(this.data);

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

class OxyFailure<T> extends OxyResult<T> {
  const OxyFailure(this.cause, this.stack);

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
