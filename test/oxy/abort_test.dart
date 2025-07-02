import 'dart:async';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';

void main() {
  group('AbortSignal', () {
    test('should create AbortSignal in non-aborted state', () {
      final signal = AbortSignal();
      expect(signal.aborted, isFalse);
      expect(signal.reason, isNull);
    });

    test('should abort signal when abort() is called', () {
      final signal = AbortSignal();
      expect(signal.aborted, isFalse);

      signal.abort();
      expect(signal.aborted, isTrue);
    });

    test('should abort signal with reason', () {
      final signal = AbortSignal();
      const reason = 'Test abort reason';

      signal.abort(reason);
      expect(signal.aborted, isTrue);
      expect(signal.reason, equals(reason));
    });

    test('should not abort twice - signal remains aborted', () {
      final signal = AbortSignal();
      const firstReason = 'First reason';
      const secondReason = 'Second reason';

      signal.abort(firstReason);
      expect(signal.aborted, isTrue);
      expect(signal.reason, equals(firstReason));

      // Second abort should not change the reason
      signal.abort(secondReason);
      expect(signal.aborted, isTrue);
      expect(signal.reason, equals(firstReason));
    });

    test('should abort with different types of reasons', () {
      final signal1 = AbortSignal();
      final signal2 = AbortSignal();
      final signal3 = AbortSignal();

      signal1.abort('String reason');
      signal2.abort(42);
      signal3.abort(Exception('Custom exception'));

      expect(signal1.reason, equals('String reason'));
      expect(signal2.reason, equals(42));
      expect(signal3.reason, isA<Exception>());
    });

    test('should throw when calling throwIfAborted() on aborted signal', () {
      final signal = AbortSignal();
      signal.abort('Test error');
      expect(() => signal.throwIfAborted(), throwsA('Test error'));
    });

    test(
      'should not throw when calling throwIfAborted() on non-aborted signal',
      () {
        final signal = AbortSignal();
        expect(() => signal.throwIfAborted(), returnsNormally);
      },
    );

    test('should throw default reason when no reason provided', () {
      final signal = AbortSignal();
      signal.abort();
      expect(() => signal.throwIfAborted(), throwsA('aborted'));
    });

    test('should throw with complex reason objects', () {
      final signal = AbortSignal();
      final customError = Exception('Custom error message');
      signal.abort(customError);
      expect(() => signal.throwIfAborted(), throwsA(customError));
    });
  });

  group('AbortSignal onAbort callbacks', () {
    test('should call callback when signal is aborted', () {
      final signal = AbortSignal();
      var callbackCalled = false;

      signal.onAbort(() {
        callbackCalled = true;
      });

      expect(callbackCalled, isFalse);
      signal.abort();
      expect(callbackCalled, isTrue);
    });

    test('should call callback immediately if signal is already aborted', () {
      final signal = AbortSignal();
      signal.abort();

      var callbackCalled = false;
      signal.onAbort(() {
        callbackCalled = true;
      });

      expect(callbackCalled, isTrue);
    });

    test('should call multiple callbacks when signal is aborted', () {
      final signal = AbortSignal();
      var callback1Called = false;
      var callback2Called = false;
      var callback3Called = false;

      signal.onAbort(() => callback1Called = true);
      signal.onAbort(() => callback2Called = true);
      signal.onAbort(() => callback3Called = true);

      expect(callback1Called, isFalse);
      expect(callback2Called, isFalse);
      expect(callback3Called, isFalse);

      signal.abort();

      expect(callback1Called, isTrue);
      expect(callback2Called, isTrue);
      expect(callback3Called, isTrue);
    });

    test('should handle callback exceptions gracefully', () {
      final signal = AbortSignal();
      var goodCallbackCalled = false;

      signal.onAbort(() {
        throw Exception('Bad callback');
      });

      signal.onAbort(() {
        goodCallbackCalled = true;
      });

      // Should not throw even if callback throws
      expect(() => signal.abort(), returnsNormally);
      expect(goodCallbackCalled, isTrue);
    });

    test('should clear callbacks after abort', () {
      final signal = AbortSignal();
      var callCount = 0;

      signal.onAbort(() => callCount++);
      signal.onAbort(() => callCount++);

      signal.abort();
      expect(callCount, equals(2));

      // Adding new callback after abort should call it immediately
      signal.onAbort(() => callCount++);
      expect(callCount, equals(3));
    });
  });

  group('AbortSignal integration scenarios', () {
    test('should work with simulated async operation', () async {
      final signal = AbortSignal();
      var operationCompleted = false;
      var operationAborted = false;

      // Simulate an async operation that respects abort signal
      Future<void> simulateOperation(AbortSignal signal) async {
        signal.onAbort(() {
          operationAborted = true;
        });

        for (int i = 0; i < 10; i++) {
          signal.throwIfAborted();
          await Future.delayed(Duration(milliseconds: 10));
        }

        operationCompleted = true;
      }

      // Start operation
      final operationFuture = simulateOperation(signal);

      // Abort after 50ms
      Timer(Duration(milliseconds: 50), () => signal.abort('User cancelled'));

      // Wait for operation to complete or abort
      try {
        await operationFuture;
        fail('Operation should have been aborted');
      } catch (e) {
        expect(e, equals('User cancelled'));
      }

      expect(operationCompleted, isFalse);
      expect(operationAborted, isTrue);
    });

    test('should work with timeout scenario', () async {
      final signal = AbortSignal();
      var timeoutTriggered = false;

      // Set up timeout
      Timer(Duration(milliseconds: 100), () {
        timeoutTriggered = true;
        signal.abort('Timeout');
      });

      // Simulate long-running operation
      try {
        await Future.delayed(Duration(milliseconds: 200));
        signal.throwIfAborted();
        fail('Should have timed out');
      } catch (e) {
        expect(e, equals('Timeout'));
        expect(timeoutTriggered, isTrue);
      }
    });

    test('should handle multiple signals independently', () {
      final signal1 = AbortSignal();
      final signal2 = AbortSignal();

      var signal1Aborted = false;
      var signal2Aborted = false;

      signal1.onAbort(() => signal1Aborted = true);
      signal2.onAbort(() => signal2Aborted = true);

      // Abort only first signal
      signal1.abort();

      expect(signal1Aborted, isTrue);
      expect(signal2Aborted, isFalse);
      expect(signal1.aborted, isTrue);
      expect(signal2.aborted, isFalse);
    });

    test('should work with HTTP request simulation', () async {
      final signal = AbortSignal();

      Future<String> simulateHttpRequest(AbortSignal signal) async {
        // Simulate network delay
        for (int i = 0; i < 5; i++) {
          signal.throwIfAborted();
          await Future.delayed(Duration(milliseconds: 20));
        }

        return 'Response data';
      }

      // Start request
      final requestFuture = simulateHttpRequest(signal);

      // Cancel request after 50ms
      Timer(Duration(milliseconds: 50), () => signal.abort('User cancelled'));

      // Should throw due to abort
      expect(requestFuture, throwsA('User cancelled'));
    });
  });

  group('AbortSignal edge cases', () {
    test('should handle null reason gracefully', () {
      final signal = AbortSignal();
      signal.abort(null);

      expect(signal.aborted, isTrue);
      expect(signal.reason, isNull);
      expect(() => signal.throwIfAborted(), throwsA('aborted'));
    });

    test('should handle empty string reason', () {
      final signal = AbortSignal();
      signal.abort('');

      expect(signal.reason, equals(''));
      expect(() => signal.throwIfAborted(), throwsA(''));
    });

    test('should maintain state consistency after multiple operations', () {
      final signal = AbortSignal();

      // Initial state
      expect(signal.aborted, isFalse);
      expect(signal.reason, isNull);

      // Add callbacks
      var callbackCount = 0;
      signal.onAbort(() => callbackCount++);
      signal.onAbort(() => callbackCount++);

      // Abort
      signal.abort('test reason');

      expect(signal.aborted, isTrue);
      expect(signal.reason, equals('test reason'));
      expect(callbackCount, equals(2));

      // Try to abort again
      signal.abort('different reason');

      expect(signal.aborted, isTrue);
      expect(signal.reason, equals('test reason')); // Should not change
      expect(callbackCount, equals(2)); // Should not increase

      // Add callback after abort
      signal.onAbort(() => callbackCount++);
      expect(callbackCount, equals(3)); // Should be called immediately
    });
  });
}
