import 'dart:async';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';

void main() {
  group('AbortController', () {
    test('should create AbortController with signal', () {
      final controller = AbortController();
      expect(controller.signal, isA<AbortSignal>());
      expect(controller.signal.aborted, isFalse);
      expect(controller.signal.reason, isNull);
    });

    test('should abort signal when abort() is called', () {
      final controller = AbortController();
      expect(controller.signal.aborted, isFalse);

      controller.abort();
      expect(controller.signal.aborted, isTrue);
    });

    test('should abort signal with reason', () {
      final controller = AbortController();
      const reason = 'Test abort reason';

      controller.abort(reason);
      expect(controller.signal.aborted, isTrue);
      expect(controller.signal.reason, equals(reason));
    });

    test('should not abort twice - signal remains aborted', () {
      final controller = AbortController();
      const firstReason = 'First reason';
      const secondReason = 'Second reason';

      controller.abort(firstReason);
      expect(controller.signal.aborted, isTrue);
      expect(controller.signal.reason, equals(firstReason));

      // Second abort should not change the reason
      controller.abort(secondReason);
      expect(controller.signal.aborted, isTrue);
      expect(controller.signal.reason, equals(firstReason));
    });

    test('should have same signal instance', () {
      final controller = AbortController();
      final signal1 = controller.signal;
      final signal2 = controller.signal;
      expect(identical(signal1, signal2), isTrue);
    });

    test('should abort with different types of reasons', () {
      final controller1 = AbortController();
      final controller2 = AbortController();
      final controller3 = AbortController();

      controller1.abort('String reason');
      controller2.abort(42);
      controller3.abort(Exception('Custom exception'));

      expect(controller1.signal.reason, equals('String reason'));
      expect(controller2.signal.reason, equals(42));
      expect(controller3.signal.reason, isA<Exception>());
    });
  });

  group('AbortSignal', () {
    test('should create non-aborted signal by default', () {
      final controller = AbortController();
      final signal = controller.signal;
      expect(signal.aborted, isFalse);
      expect(signal.reason, isNull);
    });

    test('should throw when calling throwIfAborted() on aborted signal', () {
      final controller = AbortController();
      controller.abort('Test error');
      expect(() => controller.signal.throwIfAborted(), throwsA('Test error'));
    });

    test(
      'should not throw when calling throwIfAborted() on non-aborted signal',
      () {
        final controller = AbortController();
        expect(() => controller.signal.throwIfAborted(), returnsNormally);
      },
    );

    test('should throw default reason when no reason provided', () {
      final controller = AbortController();
      controller.abort();
      expect(() => controller.signal.throwIfAborted(), throwsA('aborted'));
    });

    test('should throw with complex reason objects', () {
      final controller = AbortController();
      final customError = Exception('Custom error message');
      controller.abort(customError);
      expect(() => controller.signal.throwIfAborted(), throwsA(customError));
    });
  });

  group('AbortSignal onAbort callbacks', () {
    test('should call callback when signal is aborted', () {
      final controller = AbortController();
      var callbackCalled = false;

      controller.signal.onAbort(() {
        callbackCalled = true;
      });

      expect(callbackCalled, isFalse);
      controller.abort();
      expect(callbackCalled, isTrue);
    });

    test('should call callback immediately if signal is already aborted', () {
      final controller = AbortController();
      controller.abort();

      var callbackCalled = false;
      controller.signal.onAbort(() {
        callbackCalled = true;
      });

      expect(callbackCalled, isTrue);
    });

    test('should call multiple callbacks when signal is aborted', () {
      final controller = AbortController();
      var callback1Called = false;
      var callback2Called = false;
      var callback3Called = false;

      controller.signal.onAbort(() => callback1Called = true);
      controller.signal.onAbort(() => callback2Called = true);
      controller.signal.onAbort(() => callback3Called = true);

      expect(callback1Called, isFalse);
      expect(callback2Called, isFalse);
      expect(callback3Called, isFalse);

      controller.abort();

      expect(callback1Called, isTrue);
      expect(callback2Called, isTrue);
      expect(callback3Called, isTrue);
    });

    test('should handle callback exceptions gracefully', () {
      final controller = AbortController();
      var goodCallbackCalled = false;

      controller.signal.onAbort(() {
        throw Exception('Bad callback');
      });

      controller.signal.onAbort(() {
        goodCallbackCalled = true;
      });

      // Should not throw even if callback throws
      expect(() => controller.abort(), returnsNormally);
      expect(goodCallbackCalled, isTrue);
    });

    test('should clear callbacks after abort', () {
      final controller = AbortController();
      var callCount = 0;

      controller.signal.onAbort(() => callCount++);
      controller.signal.onAbort(() => callCount++);

      controller.abort();
      expect(callCount, equals(2));

      // Adding new callback after abort should call it immediately
      controller.signal.onAbort(() => callCount++);
      expect(callCount, equals(3));
    });
  });

  group('AbortSignal integration scenarios', () {
    test('should work with simulated async operation', () async {
      final controller = AbortController();
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
      final operationFuture = simulateOperation(controller.signal);

      // Abort after 50ms
      Timer(
        Duration(milliseconds: 50),
        () => controller.abort('User cancelled'),
      );

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
      final controller = AbortController();
      var timeoutTriggered = false;

      // Set up timeout
      Timer(Duration(milliseconds: 100), () {
        timeoutTriggered = true;
        controller.abort('Timeout');
      });

      // Simulate long-running operation
      try {
        await Future.delayed(Duration(milliseconds: 200));
        controller.signal.throwIfAborted();
        fail('Should have timed out');
      } catch (e) {
        expect(e, equals('Timeout'));
        expect(timeoutTriggered, isTrue);
      }
    });

    test('should handle multiple controllers independently', () {
      final controller1 = AbortController();
      final controller2 = AbortController();

      var signal1Aborted = false;
      var signal2Aborted = false;

      controller1.signal.onAbort(() => signal1Aborted = true);
      controller2.signal.onAbort(() => signal2Aborted = true);

      // Abort only first controller
      controller1.abort();

      expect(signal1Aborted, isTrue);
      expect(signal2Aborted, isFalse);
      expect(controller1.signal.aborted, isTrue);
      expect(controller2.signal.aborted, isFalse);
    });

    test('should work with HTTP request simulation', () async {
      final controller = AbortController();

      Future<String> simulateHttpRequest(AbortSignal signal) async {
        // Simulate network delay
        for (int i = 0; i < 5; i++) {
          signal.throwIfAborted();
          await Future.delayed(Duration(milliseconds: 20));
        }

        return 'Response data';
      }

      // Start request
      final requestFuture = simulateHttpRequest(controller.signal);

      // Cancel request after 50ms
      Timer(
        Duration(milliseconds: 50),
        () => controller.abort('User cancelled'),
      );

      // Should throw due to abort
      expect(requestFuture, throwsA('User cancelled'));
    });
  });

  group('AbortSignal edge cases', () {
    test('should handle null reason gracefully', () {
      final controller = AbortController();
      controller.abort(null);

      expect(controller.signal.aborted, isTrue);
      expect(controller.signal.reason, isNull);
      expect(() => controller.signal.throwIfAborted(), throwsA('aborted'));
    });

    test('should handle empty string reason', () {
      final controller = AbortController();
      controller.abort('');

      expect(controller.signal.reason, equals(''));
      expect(() => controller.signal.throwIfAborted(), throwsA(''));
    });

    test('should maintain state consistency after multiple operations', () {
      final controller = AbortController();
      final signal = controller.signal;

      // Initial state
      expect(signal.aborted, isFalse);
      expect(signal.reason, isNull);

      // Add callbacks
      var callbackCount = 0;
      signal.onAbort(() => callbackCount++);
      signal.onAbort(() => callbackCount++);

      // Abort
      controller.abort('test reason');

      expect(signal.aborted, isTrue);
      expect(signal.reason, equals('test reason'));
      expect(callbackCount, equals(2));

      // Try to abort again
      controller.abort('different reason');

      expect(signal.aborted, isTrue);
      expect(signal.reason, equals('test reason')); // Should not change
      expect(callbackCount, equals(2)); // Should not increase

      // Add callback after abort
      signal.onAbort(() => callbackCount++);
      expect(callbackCount, equals(3)); // Should be called immediately
    });
  });
}
