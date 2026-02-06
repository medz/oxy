import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('OxyResult helpers', () {
    test('fold dispatches success and failure branches', () {
      final success = OxySuccess<int>(2);
      final error = StateError('boom');
      final failure = OxyFailure<int>(error, StackTrace.current);

      final successValue = success.fold<int>(
        onSuccess: (value) => value * 2,
        onFailure: (_, _) => -1,
      );
      final failureValue = failure.fold<int>(
        onSuccess: (value) => value * 2,
        onFailure: (_, _) => -1,
      );

      expect(successValue, 4);
      expect(failureValue, -1);
    });

    test('map transforms success value', () {
      final result = OxySuccess<int>(2).map<String>((value) => 'v:$value');

      expect(result, isA<OxySuccess<String>>());
      expect(result.value, 'v:2');
    });

    test('map keeps failure untouched', () {
      final error = StateError('boom');
      final trace = StackTrace.current;
      final result = OxyFailure<int>(
        error,
        trace,
      ).map<String>((value) => 'v:$value');

      expect(result.isFailure, isTrue);
      expect(result.error, same(error));
      expect(result.trace, same(trace));
    });

    test('map captures mapper throw as OxyFailure', () {
      final result = OxySuccess<int>(
        1,
      ).map<String>((_) => throw const FormatException('bad map'));

      expect(result.isFailure, isTrue);
      expect(result.error, isA<FormatException>());
    });

    test('getOrThrow returns value on success', () {
      final result = OxySuccess<String>('ok');
      expect(result.getOrThrow(), 'ok');
    });

    test('getOrThrow throws original failure error', () {
      final error = StateError('boom');
      final result = OxyFailure<String>(error, StackTrace.current);

      expect(() => result.getOrThrow(), throwsA(same(error)));
    });
  });
}
