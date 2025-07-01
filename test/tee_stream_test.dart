import 'dart:async';

import 'package:test/test.dart';
import 'package:oxy/src/_internal/tee_stream_to_two_streams.dart';

void main() {
  group('teeStreamToTwoStreams', () {
    test(
      'should split single value stream into two identical streams',
      () async {
        final source = Stream.value(42);
        final (stream1, stream2) = teeStreamToTwoStreams(source);

        final value1 = await stream1.single;
        final value2 = await stream2.single;

        expect(value1, equals(42));
        expect(value2, equals(42));
      },
    );

    test('should handle multiple values correctly', () async {
      final controller = StreamController<int>();
      final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

      final future1 = stream1.toList();
      final future2 = stream2.toList();

      controller.add(1);
      controller.add(2);
      controller.add(3);
      controller.close();

      final values1 = await future1;
      final values2 = await future2;

      expect(values1, equals([1, 2, 3]));
      expect(values2, equals([1, 2, 3]));
    });

    test('should handle empty stream', () async {
      final source = Stream<int>.empty();
      final (stream1, stream2) = teeStreamToTwoStreams(source);

      final values1 = await stream1.toList();
      final values2 = await stream2.toList();

      expect(values1, isEmpty);
      expect(values2, isEmpty);
    });

    test('should propagate errors to both streams', () async {
      final controller = StreamController<int>();
      final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

      final future1 = stream1.toList();
      final future2 = stream2.toList();

      controller.addError('test error');

      expect(future1, throwsA('test error'));
      expect(future2, throwsA('test error'));
    });

    test('should work when only one stream is listened to', () async {
      final source = Stream.fromIterable([1, 2, 3]);
      final (stream1, stream2) = teeStreamToTwoStreams(source);

      // Only listen to stream1
      final values = await stream1.toList();
      expect(values, equals([1, 2, 3]));

      // stream2 is never listened to, but this shouldn't cause issues
    });

    test(
      'should work when streams are listened to at different times',
      () async {
        final controller = StreamController<int>();
        final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

        // Start listening to stream1 first
        final future1 = stream1.toList();

        controller.add(1);
        controller.add(2);

        // Start listening to stream2 later
        final future2 = stream2.toList();

        controller.add(3);
        controller.close();

        final values1 = await future1;
        final values2 = await future2;

        expect(values1, equals([1, 2, 3]));
        expect(values2, equals([1, 2, 3]));
      },
    );

    test('should handle cancellation of one stream', () async {
      final controller = StreamController<int>();
      final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

      final future1 = stream1.toList();
      final subscription2 = stream2.listen((_) {});

      controller.add(1);
      controller.add(2);

      // Cancel stream2
      await subscription2.cancel();

      controller.add(3);
      controller.close();

      final values1 = await future1;
      expect(values1, equals([1, 2, 3]));
    });

    test('should cancel source when both streams are cancelled', () async {
      final controller = StreamController<int>();
      var sourceCancelled = false;

      controller.onCancel = () {
        sourceCancelled = true;
      };

      final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

      final subscription1 = stream1.listen((_) {});
      final subscription2 = stream2.listen((_) {});

      controller.add(1);

      // Cancel both streams
      await subscription1.cancel();
      expect(sourceCancelled, isFalse); // Should not be cancelled yet

      await subscription2.cancel();
      expect(sourceCancelled, isTrue); // Now should be cancelled
    });

    test('should handle broadcast streams correctly', () async {
      final controller = StreamController<int>.broadcast();
      final broadcastStream = controller.stream;

      final (stream1, stream2) = teeStreamToTwoStreams(broadcastStream);

      // Both returned streams should be the same instance as the source
      expect(identical(stream1, broadcastStream), isTrue);
      expect(identical(stream2, broadcastStream), isTrue);

      // Test that they work as broadcast streams
      final future1 = stream1.toList();
      final future2 = stream2.toList();

      controller.add(1);
      controller.add(2);
      controller.add(3);
      controller.close();

      final values1 = await future1;
      final values2 = await future2;

      expect(values1, equals([1, 2, 3]));
      expect(values2, equals([1, 2, 3]));
    });

    test('should preserve data types correctly', () async {
      final source = Stream.fromIterable(['hello', 'world']);
      final (stream1, stream2) = teeStreamToTwoStreams(source);

      final values1 = await stream1.toList();
      final values2 = await stream2.toList();

      expect(values1, equals(['hello', 'world']));
      expect(values2, equals(['hello', 'world']));
      expect(values1, isA<List<String>>());
      expect(values2, isA<List<String>>());
    });

    test('should handle complex objects', () async {
      final objects = [
        {'name': 'Alice', 'age': 30},
        {'name': 'Bob', 'age': 25},
      ];
      final source = Stream.fromIterable(objects);
      final (stream1, stream2) = teeStreamToTwoStreams(source);

      final values1 = await stream1.toList();
      final values2 = await stream2.toList();

      expect(values1, equals(objects));
      expect(values2, equals(objects));
      expect(values1[0]['name'], equals('Alice'));
      expect(values2[1]['age'], equals(25));
    });

    test('should handle stream with mixed errors and data', () async {
      final controller = StreamController<int>();
      final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

      final events1 = <dynamic>[];
      final events2 = <dynamic>[];

      stream1.listen(
        (data) => events1.add(data),
        onError: (error) => events1.add('error: $error'),
      );

      stream2.listen(
        (data) => events2.add(data),
        onError: (error) => events2.add('error: $error'),
      );

      controller.add(1);
      controller.addError('first error');
      controller.add(2);
      controller.addError('second error');
      controller.add(3);
      controller.close();

      // Wait a bit for all events to be processed
      await Future.delayed(Duration(milliseconds: 10));

      expect(
        events1,
        equals([1, 'error: first error', 2, 'error: second error', 3]),
      );
      expect(
        events2,
        equals([1, 'error: first error', 2, 'error: second error', 3]),
      );
    });

    test('should handle rapid succession of events', () async {
      final controller = StreamController<int>();
      final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

      final future1 = stream1.toList();
      final future2 = stream2.toList();

      // Add many events quickly
      for (int i = 0; i < 1000; i++) {
        controller.add(i);
      }
      controller.close();

      final values1 = await future1;
      final values2 = await future2;

      final expected = List.generate(1000, (i) => i);
      expect(values1, equals(expected));
      expect(values2, equals(expected));
    });

    test('should handle paused and resumed streams', () async {
      final controller = StreamController<int>();
      final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

      final values1 = <int>[];
      final values2 = <int>[];

      final subscription1 = stream1.listen((value) {
        values1.add(value);
      });
      stream2.listen((value) {
        values2.add(value);
      });

      controller.add(1);
      controller.add(2);

      // Pause stream1
      subscription1.pause();

      controller.add(3);
      controller.add(4);

      // Resume stream1
      subscription1.resume();

      controller.add(5);
      controller.close();

      // Wait for all events to be processed
      await Future.delayed(Duration(milliseconds: 10));

      expect(values1, equals([1, 2, 3, 4, 5]));
      expect(values2, equals([1, 2, 3, 4, 5]));
    });

    test('should handle different generic types', () async {
      // Test with List<int>
      final source = Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]);
      final (stream1, stream2) = teeStreamToTwoStreams(source);

      final values1 = await stream1.toList();
      final values2 = await stream2.toList();

      expect(
        values1,
        equals([
          [1, 2],
          [3, 4],
        ]),
      );
      expect(
        values2,
        equals([
          [1, 2],
          [3, 4],
        ]),
      );
      expect(values1, isA<List<List<int>>>());
      expect(values2, isA<List<List<int>>>());
    });

    test('should maintain order of events across both streams', () async {
      final controller = StreamController<int>();
      final (stream1, stream2) = teeStreamToTwoStreams(controller.stream);

      final events1 = <String>[];
      final events2 = <String>[];

      stream1.listen((value) {
        events1.add('stream1: $value');
      });

      stream2.listen((value) {
        events2.add('stream2: $value');
      });

      // Add events with small delays to test ordering
      for (int i = 0; i < 5; i++) {
        controller.add(i);
        await Future.delayed(Duration(milliseconds: 1));
      }
      controller.close();

      await Future.delayed(Duration(milliseconds: 10));

      expect(
        events1,
        equals([
          'stream1: 0',
          'stream1: 1',
          'stream1: 2',
          'stream1: 3',
          'stream1: 4',
        ]),
      );

      expect(
        events2,
        equals([
          'stream2: 0',
          'stream2: 1',
          'stream2: 2',
          'stream2: 3',
          'stream2: 4',
        ]),
      );
    });
  });
}
