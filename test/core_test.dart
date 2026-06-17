import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('Headers', () {
    test('stores names case-insensitively and preserves multi-values', () {
      final headers = Headers({'X-Test': 'one'})
        ..append('x-test', 'two')
        ..set('Content-Type', 'text/plain');

      expect(headers.get('X-TEST'), 'one,two');
      expect(headers.getAll('x-test'), ['one', 'two']);
      expect(headers.get('content-type'), 'text/plain');
    });
  });

  group('Body', () {
    test('marks bytes and json bodies as replayable', () async {
      final bytes = Body.fromBytes([1, 2, 3]);
      final json = Body.fromJson({'ok': true});

      expect(bytes.replayable, isTrue);
      expect(await bytes.bytes(), [1, 2, 3]);
      expect(await bytes.bytes(), [1, 2, 3]);
      expect(json.contentType, contains('application/json'));
      expect(utf8.decode(await json.bytes()), '{"ok":true}');
    });

    test('protects one-shot streams from accidental replay', () async {
      final body = Body.stream(
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList([1]),
        ]),
      );

      expect(body.replayable, isFalse);
      expect(await body.bytes(), [1]);
      expect(body.bytes(), throwsA(isA<BodyStateError>()));
    });
  });

  group('Response', () {
    test('decodes json and maps typed payloads', () async {
      final response = Response.json({'name': 'oxy'});

      expect(await response.json<Map<String, Object?>>(), {'name': 'oxy'});

      final decoded = await response.decode<String>(
        decoder: (value) => (value as Map<String, Object?>)['name'] as String,
      );
      expect(decoded, 'oxy');
    });

    test('throws DecodeError for invalid json', () async {
      final response = Response.text('not-json');
      await expectLater(response.json<Object?>(), throwsA(isA<DecodeError>()));
    });
  });

  group('Result', () {
    test('captures no-throw flows without method matrices', () async {
      final result = await Result.capture(() async => 42);
      final failed = await Result.capture<int>(
        () async => throw StateError('x'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, 42);
      expect(failed.isFailure, isTrue);
      expect(failed.error, isA<StateError>());
    });
  });
}
