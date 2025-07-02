import 'dart:async';

import 'package:test/test.dart';
import 'package:oxy/src/_internal/mark_stream.dart';

void main() {
  group('MarkStream', () {
    test('should initialize with used as false', () {
      final source = Stream.value(42);
      final markStream = MarkStream(source);

      expect(markStream.used, isFalse);
    });

    test('should forward isBroadcast property from source stream', () {
      final singleStream = Stream.value(42);
      final broadcastStream = StreamController<int>.broadcast().stream;

      final markSingle = MarkStream(singleStream);
      final markBroadcast = MarkStream(broadcastStream);

      expect(markSingle.isBroadcast, isFalse);
      expect(markBroadcast.isBroadcast, isTrue);
    });

    test(
      'should mark single-subscription stream as used when listen is called',
      () {
        final source = Stream.value(42);
        final markStream = MarkStream(source);

        expect(markStream.used, isFalse);

        markStream.listen((_) {});

        expect(markStream.used, isTrue);
      },
    );

    test('should NOT mark broadcast stream as used when listen is called', () {
      final controller = StreamController<int>.broadcast();
      final markStream = MarkStream(controller.stream);

      expect(markStream.used, isFalse);

      markStream.listen((_) {});

      expect(markStream.used, isFalse);
    });

    test(
      'should mark as used when calling convenience methods on single-subscription stream',
      () async {
        final source = Stream.value(42);
        final markStream = MarkStream(source);

        expect(markStream.used, isFalse);

        await markStream.first;

        expect(markStream.used, isTrue);
      },
    );

    test(
      'should NOT mark broadcast stream as used with convenience methods',
      () async {
        final controller = StreamController<int>.broadcast();
        final markStream = MarkStream(controller.stream);

        expect(markStream.used, isFalse);

        // Start listening first, then add data
        final future = markStream.first;
        controller.add(42);
        controller.close();

        await future;

        expect(markStream.used, isFalse);
      },
    );

    test('should remain used once marked', () async {
      final source = Stream.value(42);
      final markStream = MarkStream(source);

      expect(markStream.used, isFalse);

      await markStream.first;

      expect(markStream.used, isTrue);
      expect(markStream.used, isTrue); // Still true
    });

    test(
      'should allow multiple listeners on broadcast stream without marking as used',
      () {
        final controller = StreamController<int>.broadcast();
        final markStream = MarkStream(controller.stream);

        expect(markStream.used, isFalse);

        markStream.listen((_) {});
        markStream.listen((_) {});
        markStream.listen((_) {});

        expect(markStream.used, isFalse);
      },
    );

    test('should handle different generic types', () {
      final stringStream = Stream.value('hello');
      final listStream = Stream.value([1, 2, 3]);
      final mapStream = Stream.value({'key': 'value'});

      final markString = MarkStream<String>(stringStream);
      final markList = MarkStream<List<int>>(listStream);
      final markMap = MarkStream<Map<String, String>>(mapStream);

      expect(markString.used, isFalse);
      expect(markList.used, isFalse);
      expect(markMap.used, isFalse);

      markString.listen((_) {});
      markList.listen((_) {});
      markMap.listen((_) {});

      expect(markString.used, isTrue);
      expect(markList.used, isTrue);
      expect(markMap.used, isTrue);
    });
  });
}
