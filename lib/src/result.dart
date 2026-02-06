sealed class OxyResult<T> {
  const OxyResult();

  bool get isSuccess;
  bool get isFailure => !isSuccess;

  T? get value;
  Object? get error;
  StackTrace? get trace;
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
