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

    test('isolates replayable byte reads from caller mutation', () async {
      final body = Body.fromBytes([1, 2, 3]);

      final first = await body.bytes();
      first[0] = 9;

      expect(await body.bytes(), [1, 2, 3]);
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

    test('accepts built-in form primitives backed by ht', () async {
      final form = FormData()
        ..append('name', const Multipart.text('oxy'))
        ..append(
          'file',
          Multipart.blob(Blob(['hello'], 'text/plain'), 'a.txt'),
        );
      final body = Body.from(form)!;

      expect(body.kind, BodyKind.multipart);
      expect(body.replayable, isTrue);
      expect(body.contentType, startsWith('multipart/form-data; boundary='));
      expect(body.contentLength, greaterThan(0));

      final text = utf8.decode(await body.bytes());
      expect(text, contains('name="name"'));
      expect(text, contains('oxy'));
      expect(text, contains('filename="a.txt"'));
      expect(utf8.decode(await body.bytes()), text);
    });

    test('treats Blob bodies as streaming file-like bodies', () async {
      final body = Body.from(Blob(['hello'], 'text/plain'))!;

      expect(body.kind, BodyKind.file);
      expect(body.replayable, isTrue);
      expect(body.contentLength, 5);
      expect(body.contentType, 'text/plain');
      expect(await body.text(), 'hello');
      expect(await body.text(), 'hello');
    });

    test('accepts URLSearchParams as replayable form body', () async {
      final params = URLSearchParams({'q': 'oxy', 'page': '1'});
      final body = Body.from(params)!;

      expect(body.kind, BodyKind.form);
      expect(body.contentType, contains('application/x-www-form-urlencoded'));
      expect(await body.text(), 'q=oxy&page=1');
      expect(await body.text(), 'q=oxy&page=1');
    });
  });

  group('AbortSignal', () {
    test('swallows late abort callback failures consistently', () {
      final signal = AbortSignal()..abort('done');

      expect(
        () => signal.onAbort(() => throw StateError('late')),
        returnsNormally,
      );
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

    test('isolates replayable response bytes from caller mutation', () async {
      final response = Response.bytes([1, 2, 3]);

      final first = await response.bytes();
      first[0] = 9;
      final chunk = await response.stream().single;
      chunk[1] = 8;

      expect(await response.bytes(), [1, 2, 3]);
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
