import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('AbortSignal', () {
    test('starts non-aborted', () {
      final signal = AbortSignal();
      expect(signal.aborted, isFalse);
      expect(signal.reason, isNull);
    });

    test('stores reason and throws after abort', () {
      final signal = AbortSignal();
      signal.abort('cancelled');

      expect(signal.aborted, isTrue);
      expect(signal.reason, 'cancelled');
      expect(signal.throwIfAborted, throwsA('cancelled'));
    });

    test('invokes callback immediately when already aborted', () {
      final signal = AbortSignal()..abort('done');
      var called = false;

      signal.onAbort(() {
        called = true;
      });

      expect(called, isTrue);
    });
  });
}
