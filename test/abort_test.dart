import 'dart:async';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';

// Platform detection
bool get isWeb => identical(0, 0.0);

void main() {
  group('AbortController', () {
    test('should create AbortController with signal', () {
      final controller = AbortController();
      expect(controller.signal, isA<AbortSignal>());
      expect(controller.signal.aborted, isFalse);
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
  });

  group('AbortSignal', () {
    test('should create non-aborted signal by default', () {
      final controller = AbortController();
      final signal = controller.signal;
      expect(signal.aborted, isFalse);
      expect(signal.reason, isNull);
    });

    test('should create aborted signal with AbortSignal.abort()', () {
      final signal = AbortSignal.abort();
      expect(signal.aborted, isTrue);
    });

    test('should create aborted signal with reason', () {
      const reason = 'Custom abort reason';
      final signal = AbortSignal.abort(reason);
      expect(signal.aborted, isTrue);
      expect(signal.reason, equals(reason));
    });

    test('should throw when calling throwIfAborted() on aborted signal', () {
      final signal = AbortSignal.abort('Test error');
      expect(() => signal.throwIfAborted(), throwsA('Test error'));
    });

    test(
      'should not throw when calling throwIfAborted() on non-aborted signal',
      () {
        final controller = AbortController();
        expect(() => controller.signal.throwIfAborted(), returnsNormally);
      },
    );

    test('should throw default reason when no reason provided', () {
      final signal = AbortSignal.abort();
      expect(() => signal.throwIfAborted(), throwsA(anything));
    });
  });

  group('AbortSignal.timeout()', () {
    test('should create signal that aborts after timeout', () async {
      final signal = AbortSignal.timeout(100);
      expect(signal.aborted, isFalse);

      await Future.delayed(Duration(milliseconds: 150));
      expect(signal.aborted, isTrue);

      if (isWeb) {
        // On web, reason is a DOMException object
        expect(signal.reason.toString(), contains('TimeoutError'));
      } else {
        // On native, reason is a string
        expect(signal.reason, equals('TimeoutError'));
      }
    });

    test('should throw TimeoutError when timeout signal is checked', () async {
      final signal = AbortSignal.timeout(50);
      await Future.delayed(Duration(milliseconds: 100));

      if (isWeb) {
        expect(() => signal.throwIfAborted(), throwsA(anything));
      } else {
        expect(() => signal.throwIfAborted(), throwsA('TimeoutError'));
      }
    });

    test('should create immediately aborted signal with 0 timeout', () async {
      final signal = AbortSignal.timeout(0);

      // Give a micro task for the timer to execute
      await Future.delayed(Duration.zero);

      expect(signal.aborted, isTrue);

      if (isWeb) {
        // On web, reason is a DOMException object
        expect(signal.reason.toString(), contains('TimeoutError'));
      } else {
        // On native, reason is a string
        expect(signal.reason, equals('TimeoutError'));
      }
    });
  });

  group('AbortSignal Events', () {
    test('should trigger abort event when signal is aborted', () async {
      final controller = AbortController();
      var eventFired = false;
      Event? capturedEvent;

      // Skip addEventListener test on web due to JS interop issues
      if (isWeb) {
        // Test onabort callback instead on web
        controller.signal.onabort = (event) {
          eventFired = true;
          capturedEvent = event;
        };
      } else {
        controller.signal.addEventListener('abort', (event) {
          eventFired = true;
          capturedEvent = event;
        });
      }

      expect(eventFired, isFalse);
      controller.abort();

      // Give a small delay for event to propagate
      await Future.delayed(Duration.zero);

      expect(eventFired, isTrue);
      expect(capturedEvent?.type, equals('abort'));
      if (!isWeb) {
        expect(capturedEvent?.target, equals(controller.signal));
      }
    });

    test('should trigger onabort callback when signal is aborted', () async {
      final controller = AbortController();
      var callbackFired = false;
      Event? capturedEvent;

      controller.signal.onabort = (event) {
        callbackFired = true;
        capturedEvent = event;
      };

      expect(callbackFired, isFalse);
      controller.abort();

      // Give a small delay for callback to execute
      await Future.delayed(Duration.zero);

      expect(callbackFired, isTrue);
      expect(capturedEvent?.type, equals('abort'));
    });

    test('should trigger both addEventListener and onabort', () async {
      final controller = AbortController();
      var eventListenerFired = false;
      var onabortFired = false;

      if (!isWeb) {
        controller.signal.addEventListener('abort', (event) {
          eventListenerFired = true;
        });
      }

      controller.signal.onabort = (event) {
        onabortFired = true;
      };

      controller.abort();
      await Future.delayed(Duration.zero);

      if (!isWeb) {
        expect(eventListenerFired, isTrue);
      }
      expect(onabortFired, isTrue);
    });

    test(
      'should not trigger event multiple times when already aborted',
      () async {
        final controller = AbortController();
        var eventCount = 0;

        if (isWeb) {
          controller.signal.onabort = (event) {
            eventCount++;
          };
        } else {
          controller.signal.addEventListener('abort', (event) {
            eventCount++;
          });
        }

        controller.abort();
        controller.abort(); // Second abort should not trigger event

        // Give a small delay for events to propagate
        await Future.delayed(Duration.zero);

        expect(eventCount, equals(1));
      },
    );

    test('should trigger event for timeout signal', () async {
      final signal = AbortSignal.timeout(50);
      final completer = Completer<bool>.sync();

      signal.addEventListener('abort', (_) {
        completer.complete(true);
      });

      expect(await completer.future, isTrue);
    });

    test('should not trigger event on already aborted signal', () async {
      final signal = AbortSignal.abort();
      var eventCount = 0;

      signal.addEventListener('abort', (event) {
        eventCount++;
      });

      expect(eventCount, equals(0));
    });
  });

  group('EventTarget addEventListener/removeEventListener', () {
    test('should add and remove event listeners correctly', () async {
      final controller = AbortController();
      var eventCount = 0;

      void listener(Event event) {
        eventCount++;
      }

      controller.signal.addEventListener('abort', listener);
      controller.abort();

      expect(eventCount, equals(1));

      // Remove listener and abort again (though signal is already aborted)
      controller.signal.removeEventListener('abort', listener);

      // Create new controller to test removal
      final controller2 = AbortController();
      controller2.signal.addEventListener('abort', listener);
      controller2.signal.removeEventListener('abort', listener);
      controller2.abort();

      expect(eventCount, equals(1)); // Should still be 1
    });

    test('should support once option', () async {
      final controller = AbortController();
      var eventCount = 0;

      controller.signal.addEventListener('abort', (event) {
        eventCount++;
      }, once: true);

      controller.abort();
      await Future.delayed(Duration.zero);
      expect(eventCount, equals(1));

      // Listener should be automatically removed after first call
      // So aborting again shouldn't increase count (though signal is already aborted)
      final controller2 = AbortController();
      controller2.signal.addEventListener('abort', (event) {
        eventCount++;
      }, once: true);

      controller2.abort();

      expect(eventCount, equals(2)); // Increased by new controller
    });

    test('should support signal option for automatic cleanup', () async {
      final controller = AbortController();
      final cleanupController = AbortController();
      var eventCount = 0;

      controller.signal.addEventListener('abort', (event) {
        eventCount++;
      }, signal: cleanupController.signal);

      // Abort the cleanup signal first
      cleanupController.abort();

      // Now abort the main signal - listener should not fire
      controller.abort();

      expect(eventCount, equals(0));
    });
  });

  group('Event object properties', () {
    test('should have correct event properties', () async {
      final controller = AbortController();
      Event? capturedEvent;

      controller.signal.addEventListener('abort', (event) {
        capturedEvent = event;
      });

      controller.abort();

      expect(capturedEvent, isNotNull);
      expect(capturedEvent!.type, equals('abort'));
      expect(capturedEvent!.bubbles, isFalse);
      expect(capturedEvent!.cancelable, isFalse);
      expect(capturedEvent!.target, equals(controller.signal));
      expect(capturedEvent!.currentTarget, equals(controller.signal));
      expect(capturedEvent!.defaultPrevented, isFalse);
      expect(capturedEvent!.timeStamp, isA<num>());
    });

    test('should prevent default if cancelable', () async {
      final controller = AbortController();
      Event? capturedEvent;

      controller.signal.addEventListener('abort', (event) {
        capturedEvent = event;
        event.preventDefault();
      });

      controller.abort();

      // Abort event is not cancelable by default
      expect(capturedEvent!.defaultPrevented, isFalse);
    });
  });

  group('AbortSignal.any()', () {
    test('should create signal that aborts when any source signal aborts', () {
      final controller1 = AbortController();
      final controller2 = AbortController();
      final anySignal = AbortSignal.any([
        controller1.signal,
        controller2.signal,
      ]);

      expect(anySignal.aborted, isFalse);

      controller1.abort('reason1');
      expect(anySignal.aborted, isTrue);
      expect(anySignal.reason, equals('reason1'));
    });

    test(
      'should abort immediately if any source signal is already aborted',
      () {
        final controller1 = AbortController();
        final abortedSignal = AbortSignal.abort('already aborted');
        final anySignal = AbortSignal.any([controller1.signal, abortedSignal]);

        expect(anySignal.aborted, isTrue);
        expect(anySignal.reason, equals('already aborted'));
      },
    );

    test('should trigger event when any signal aborts', () async {
      final controller1 = AbortController();
      final controller2 = AbortController();
      final anySignal = AbortSignal.any([
        controller1.signal,
        controller2.signal,
      ]);

      var eventFired = false;
      anySignal.addEventListener('abort', (event) {
        eventFired = true;
      });

      controller2.abort();

      expect(eventFired, isTrue);
    });

    test('should work with timeout signals', () async {
      final controller = AbortController();
      final timeoutSignal = AbortSignal.timeout(100);
      final anySignal = AbortSignal.any([controller.signal, timeoutSignal]);

      expect(anySignal.aborted, isFalse);

      await Future.delayed(Duration(milliseconds: 150));
      expect(anySignal.aborted, isTrue);
      expect(anySignal.reason.toString(), contains('TimeoutError'));
    });

    test('should handle empty signal array', () {
      final anySignal = AbortSignal.any([]);
      expect(anySignal.aborted, isFalse);
    });
  });

  group('Edge cases and error conditions', () {
    test('should handle null reason gracefully', () {
      final controller = AbortController();
      controller.abort(null);

      expect(controller.signal.aborted, isTrue);
      expect(controller.signal.reason, isNull);
    });

    test('should handle complex objects as reasons', () {
      final controller = AbortController();
      final complexReason = {'error': 'custom', 'code': 123};

      controller.abort(complexReason);
      expect(controller.signal.reason, equals(complexReason));
    });

    test('should maintain event listener order', () async {
      final controller = AbortController();
      final callOrder = <int>[];

      controller.signal.addEventListener('abort', (event) {
        callOrder.add(1);
      });

      controller.signal.addEventListener('abort', (event) {
        callOrder.add(2);
      });

      controller.signal.addEventListener('abort', (event) {
        callOrder.add(3);
      });

      controller.abort();

      expect(callOrder, equals([1, 2, 3]));
    });

    test('should handle event listener exceptions gracefully', () async {
      final controller = AbortController();
      var secondListenerCalled = false;

      controller.signal.addEventListener('abort', (event) {
        throw Exception('Listener error');
      });

      controller.signal.addEventListener('abort', (event) {
        secondListenerCalled = true;
      });

      expect(() {
        controller.abort();
      }, returnsNormally);

      // Second listener should still be called despite first one throwing
      expect(secondListenerCalled, isTrue);
    });

    test('should support removing listeners during event dispatch', () async {
      final controller = AbortController();
      var listener1Called = false;
      var listener2Called = false;

      void listener2(Event event) {
        listener2Called = true;
      }

      void listener1(Event event) {
        listener1Called = true;
        controller.signal.removeEventListener('abort', listener2);
      }

      controller.signal.addEventListener('abort', listener1);
      controller.signal.addEventListener('abort', listener2);

      controller.abort();
      await Future.delayed(Duration.zero);

      expect(listener1Called, isTrue);
      // Behavior may vary - this tests the implementation's specific behavior
    });
  });

  group('Memory and resource management', () {
    test('should clean up timeout resources', () async {
      // Create many timeout signals to test resource cleanup
      final signals = <AbortSignal>[];
      for (int i = 0; i < 100; i++) {
        signals.add(AbortSignal.timeout(10));
      }

      await Future.delayed(Duration(milliseconds: 50));

      // All signals should be aborted
      for (final signal in signals) {
        expect(signal.aborted, isTrue);
      }
    });

    test('should handle rapid abort/create cycles', () {
      for (int i = 0; i < 1000; i++) {
        final controller = AbortController();
        controller.abort('test $i');
        expect(controller.signal.aborted, isTrue);
      }
    });
  });

  group('Integration scenarios', () {
    test('should work in typical fetch-like scenario', () async {
      final controller = AbortController();
      var operationAborted = false;
      var cleanupCalled = false;

      // Simulate async operation that can be aborted
      Future<String> simulatedFetch() async {
        try {
          for (int i = 0; i < 10; i++) {
            controller.signal.throwIfAborted();
            await Future.delayed(Duration(milliseconds: 10));
          }
          return 'Success';
        } catch (e) {
          operationAborted = true;
          cleanupCalled = true;
          rethrow;
        }
      }

      final fetchFuture = simulatedFetch();

      // Abort after 50ms
      Future.delayed(Duration(milliseconds: 50), () {
        controller.abort('User cancelled');
      });

      expect(() => fetchFuture, throwsA('User cancelled'));
      await Future.delayed(Duration(milliseconds: 100));

      expect(operationAborted, isTrue);
      expect(cleanupCalled, isTrue);
    });

    test('should support chained operations with different signals', () async {
      final controller1 = AbortController();
      final controller2 = AbortController();
      final combinedSignal = AbortSignal.any([
        controller1.signal,
        controller2.signal,
      ]);

      var step1Completed = false;
      var step2Aborted = false;

      // Step 1
      try {
        controller1.signal.throwIfAborted();
        step1Completed = true;
      } catch (e) {
        // Should not abort here
      }

      // Step 2 with combined signal
      try {
        combinedSignal.throwIfAborted();
        await Future.delayed(Duration(milliseconds: 10));
        combinedSignal.throwIfAborted();
      } catch (e) {
        step2Aborted = true;
      }

      // Abort second controller
      controller2.abort('Step 2 cancelled');

      try {
        combinedSignal.throwIfAborted();
      } catch (e) {
        step2Aborted = true;
      }

      expect(step1Completed, isTrue);
      expect(step2Aborted, isTrue);
      expect(combinedSignal.aborted, isTrue);
    });
  });
}
