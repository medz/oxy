import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;
import 'package:oxy/oxy.dart';
import 'package:oxy/src/transport/transport.stub.dart' as stub;
import 'package:test/test.dart';

void main() {
  group('Headers', () {
    test('stores names case-insensitively through ht', () {
      final headers = Headers({'X-Test': 'one'})
        ..append('x-test', 'two')
        ..set('Content-Type', 'text/plain');

      expect(headers.get('X-TEST'), 'one, two');
      expect(headers.entries().map((entry) => entry.key), contains('x-test'));
      expect(headers.get('content-type'), 'text/plain');
    });

    test('preserves set-cookie as independent values', () {
      final headers = Headers()
        ..append('set-cookie', 'a=1')
        ..append('set-cookie', 'b=2');

      expect(headers.get('set-cookie'), isNull);
      expect(headers.getSetCookie(), ['a=1', 'b=2']);
    });

    test('copies independently from headers', () {
      final headers = Headers({'x-id': '1'});
      final copy = Headers(headers)..set('x-id', '2');

      expect(headers.get('x-id'), '1');
      expect(copy.get('x-id'), '2');
    });
  });

  group('Body', () {
    test('marks bytes and json bodies as replayable', () async {
      final bytes = Body.fromBytes([1, 2, 3]);
      final text = Body.from('hello')!;
      final json = Body.fromJson({'ok': true});

      expect(bytes.replayable, isTrue);
      expect(await bytes.bytes(), [1, 2, 3]);
      expect(await bytes.bytes(), [1, 2, 3]);
      expect(text.kind, BodyKind.text);
      expect(text.contentType, 'text/plain;charset=UTF-8');
      expect(await text.text(), 'hello');
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

      final boundary = body.contentType!.split('boundary=').last;
      final text = utf8.decode(await body.bytes());
      expect(text, startsWith('--$boundary\r\n'));
      expect(text, endsWith('--$boundary--\r\n'));
      expect(text, contains('name="name"'));
      expect(text, contains('oxy'));
      expect(text, contains('filename="a.txt"'));
      expect(utf8.decode(await body.bytes()), text);
    });

    test('treats Blob and File bodies as streaming file-like bodies', () async {
      final body = Body.from(Blob(['hello'], 'text/plain'))!;
      final fileBody = Body.from(File(['file'], 'a.txt', type: 'text/plain'))!;

      expect(body.kind, BodyKind.file);
      expect(body.replayable, isTrue);
      expect(body.contentLength, 5);
      expect(body.contentType, 'text/plain');
      expect(await body.text(), 'hello');
      expect(await body.text(), 'hello');

      expect(fileBody.kind, BodyKind.file);
      expect(fileBody.replayable, isTrue);
      expect(fileBody.contentLength, 4);
      expect(fileBody.contentType, 'text/plain');
      expect(await fileBody.text(), 'file');
      expect(await fileBody.text(), 'file');
    });

    test('accepts URLSearchParams as replayable form body', () async {
      final params = URLSearchParams({'q': 'oxy', 'page': '1'});
      final body = Body.from(params)!;

      expect(body.kind, BodyKind.form);
      expect(
        body.contentType,
        'application/x-www-form-urlencoded;charset=UTF-8',
      );
      expect(await body.text(), 'q=oxy&page=1');
      expect(await body.text(), 'q=oxy&page=1');
    });

    test('accepts ht Body as replayable upstream body', () async {
      final upstream = ht.Body('hello');
      final body = Body.from(upstream)!;

      expect(body.kind, BodyKind.stream);
      expect(body.replayable, isTrue);
      expect(body.contentLength, isNull);
      expect(body.contentType, 'text/plain;charset=UTF-8');
      expect(await body.text(), 'hello');
      expect(await body.text(), 'hello');
      expect(upstream.bodyUsed, isFalse);
    });

    test('accepts stream-backed ht Body through clone semantics', () async {
      final upstream = ht.Body(
        Stream<List<int>>.fromIterable([
          utf8.encode('hello '),
          utf8.encode('stream'),
        ]),
      );
      final body = Body.from(upstream)!;

      expect(body.replayable, isTrue);
      expect(await body.text(), 'hello stream');
      expect(await body.text(), 'hello stream');
    });

    test('accepts ByteBuffer through ht-compatible body input', () async {
      final buffer = Uint8List.fromList([1, 2, 3]).buffer;
      final body = Body.from(buffer)!;

      expect(body.kind, BodyKind.bytes);
      expect(body.replayable, isTrue);
      expect(body.contentLength, 3);
      expect(await body.bytes(), [1, 2, 3]);
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

  group('Transport', () {
    test('unsupported transport failures are non-retryable', () async {
      final transport = stub.createTransport();

      await expectLater(
        transport.send(
          Request('https://example.com'),
          Context(
            clientOptions: const ClientOptions(),
            requestOptions: const RequestOptions(),
            timeoutPolicy: const TimeoutPolicy(),
            retryPolicy: const RetryPolicy(),
            redirectPolicy: RedirectPolicy.follow,
            statusPolicy: StatusPolicy.throwOnError,
            capability: transport.capability,
            attributes: const Attributes(),
            createdAt: DateTime.now().toUtc(),
            attempt: 0,
          ),
        ),
        throwsA(
          isA<NetworkError>().having(
            (error) => error.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
    });
  });
}
