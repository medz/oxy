@TestOn("chrome")
library;

import 'dart:async';
import 'dart:typed_data';
import "dart:js_interop";
import 'package:oxy/src/_internal/web_stream_utils.dart';
import 'package:test/test.dart';

void main() {
  group('WebStreamUtils', () {
    group('toWebReadableStream', () {
      test('converts simple dart stream to web readable stream', () async {
        // Create a simple Dart stream
        final data = [
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([4, 5, 6]),
          Uint8List.fromList([7, 8, 9]),
        ];
        final dartStream = Stream.fromIterable(data);

        // Convert to web readable stream
        final webStream = toWebReadableStream(dartStream);
        expect(webStream, isNotNull);

        // Convert back to dart stream and verify data
        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, hasLength(3));
        expect(result[0], equals([1, 2, 3]));
        expect(result[1], equals([4, 5, 6]));
        expect(result[2], equals([7, 8, 9]));
      });

      test('handles empty stream', () async {
        final dartStream = Stream<Uint8List>.empty();
        final webStream = toWebReadableStream(dartStream);

        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, isEmpty);
      });

      test('handles single item stream', () async {
        final data = Uint8List.fromList([42, 43, 44]);
        final dartStream = Stream.value(data);

        final webStream = toWebReadableStream(dartStream);
        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, hasLength(1));
        expect(result[0], equals([42, 43, 44]));
      });

      test('handles large data chunks', () async {
        final largeData = Uint8List(1000);
        for (int i = 0; i < 1000; i++) {
          largeData[i] = i % 256;
        }

        final dartStream = Stream.value(largeData);
        final webStream = toWebReadableStream(dartStream);
        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, hasLength(1));
        expect(result[0], hasLength(1000));
        expect(result[0][0], equals(0));
        expect(result[0][999], equals(999 % 256));
      });
    });

    group('toDartStream', () {
      test('reads from web readable stream correctly', () async {
        final data = [
          Uint8List.fromList([10, 20, 30]),
          Uint8List.fromList([40, 50, 60]),
        ];
        final dartStream = Stream.fromIterable(data);
        final webStream = toWebReadableStream(dartStream);

        final resultStream = toDartStream(webStream);
        final chunks = <Uint8List>[];

        await for (final chunk in resultStream) {
          chunks.add(chunk);
        }

        expect(chunks, hasLength(2));
        expect(chunks[0], equals([10, 20, 30]));
        expect(chunks[1], equals([40, 50, 60]));
      });

      test('handles stream with many small chunks', () async {
        final data = List.generate(100, (i) => Uint8List.fromList([i]));
        final dartStream = Stream.fromIterable(data);
        final webStream = toWebReadableStream(dartStream);

        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, hasLength(100));
        for (int i = 0; i < 100; i++) {
          expect(result[i], equals([i]));
        }
      });
    });

    group('round-trip conversion', () {
      test('preserves data integrity through multiple conversions', () async {
        final originalData = [
          Uint8List.fromList([255, 0, 128]),
          Uint8List.fromList([64, 192, 32]),
          Uint8List.fromList([16, 240, 8]),
        ];

        // Original Dart stream
        final stream1 = Stream.fromIterable(originalData);

        // Convert to web stream and back
        final webStream = toWebReadableStream(stream1);
        final stream2 = toDartStream(webStream);

        // Convert to web stream and back again
        final webStream2 = toWebReadableStream(stream2);
        final stream3 = toDartStream(webStream2);

        final result = await stream3.toList();

        expect(result, hasLength(3));
        expect(result[0], equals([255, 0, 128]));
        expect(result[1], equals([64, 192, 32]));
        expect(result[2], equals([16, 240, 8]));
      });

      test('handles binary data correctly', () async {
        // Test with binary data that might be problematic
        final binaryData = Uint8List(256);
        for (int i = 0; i < 256; i++) {
          binaryData[i] = i;
        }

        final dartStream = Stream.value(binaryData);
        final webStream = toWebReadableStream(dartStream);
        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, hasLength(1));
        expect(result[0], hasLength(256));

        // Verify all bytes are preserved
        for (int i = 0; i < 256; i++) {
          expect(result[0][i], equals(i));
        }
      });

      test('handles async stream generation', () async {
        // Create an async stream that yields data over time
        Stream<Uint8List> asyncStream() async* {
          for (int i = 0; i < 5; i++) {
            await Future.delayed(Duration(milliseconds: 1));
            yield Uint8List.fromList([i, i + 1, i + 2]);
          }
        }

        final webStream = toWebReadableStream(asyncStream());
        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, hasLength(5));
        for (int i = 0; i < 5; i++) {
          expect(result[i], equals([i, i + 1, i + 2]));
        }
      });
    });

    group('error handling', () {
      test('handles stream errors gracefully', () async {
        Stream<Uint8List> errorStream() async* {
          yield Uint8List.fromList([1, 2, 3]);
          throw Exception('Test error');
        }

        final webStream = toWebReadableStream(errorStream());
        final resultStream = toDartStream(webStream);

        expect(() => resultStream.toList(), throwsA(anything));
      });

      test('properly releases reader lock on error', () async {
        Stream<Uint8List> errorStream() async* {
          yield Uint8List.fromList([1, 2, 3]);
          throw Exception('Test error');
        }

        final webStream = toWebReadableStream(errorStream());
        final reader = webStream.getReader();

        // The reader should be released even if an error occurs
        try {
          while (true) {
            final result = await reader.read().toDart;
            if (result.done) break;
            if (result.value == null) continue;
            // This should eventually throw
          }
        } catch (e) {
          // Expected to throw
        } finally {
          // Reader should be releasable (no error should occur here)
          expect(() => reader.releaseLock(), returnsNormally);
        }
      });
    });

    group('edge cases', () {
      test('handles null values in stream correctly', () async {
        // Note: This tests the internal handling of null values
        final data = [
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([]), // Empty array
          Uint8List.fromList([4, 5, 6]),
        ];

        final dartStream = Stream.fromIterable(data);
        final webStream = toWebReadableStream(dartStream);
        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, hasLength(2));
        expect(result[0], equals([1, 2, 3]));
        expect(result[1], equals([4, 5, 6]));
      });

      test('handles very large streams', () async {
        // Test with a large number of small chunks
        final chunkCount = 1000;
        final data = List.generate(
          chunkCount,
          (i) => Uint8List.fromList([i % 256, (i + 1) % 256]),
        );

        final dartStream = Stream.fromIterable(data);
        final webStream = toWebReadableStream(dartStream);
        final resultStream = toDartStream(webStream);
        final result = await resultStream.toList();

        expect(result, hasLength(chunkCount));

        // Spot check some values
        expect(result[0], equals([0, 1]));
        expect(result[500], equals([244, 245])); // 500 % 256 = 244
        expect(result[999], equals([231, 232])); // 999 % 256 = 231
      });
    });
  });
}
