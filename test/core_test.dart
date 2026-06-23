import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;
import 'package:oxy/oxy.dart';
import 'package:oxy/src/core/body.dart' as internal;
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
    test('inherits ht body primitive APIs', () async {
      final text = Body('hello');

      expect(text, isA<ht.Body>());
      expect(text, isA<Blob>());
      expect(text, isA<Stream<Uint8List>>());
      expect(text.replayable, isTrue);
      expect(text.size, 5);
      expect(text.type, 'text/plain;charset=utf-8');
      expect(text.contentType, 'text/plain;charset=UTF-8');
      expect(text.bodyUsed, isFalse);

      final clone = text.clone();
      expect(clone, isA<Body>());
      expect(await clone.text(), 'hello');
      expect(text.bodyUsed, isFalse);
      expect(await text.text(), 'hello');
      expect(text.bodyUsed, isTrue);
      expect(text.text(), throwsStateError);
    });

    test('isolates cloned byte reads from caller mutation', () async {
      final body = Body([1, 2, 3]);

      final first = await body.clone().bytes();
      first[0] = 9;

      expect(await body.clone().bytes(), [1, 2, 3]);
    });

    test('protects one-shot streams from accidental replay', () async {
      final body = Body(
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList([1]),
        ]),
      );

      expect(body.replayable, isFalse);
      expect(await body.bytes(), [1]);
      expect(body.bytes(), throwsStateError);
      expect(body.clone, throwsA(isA<BodyStateError>()));
    });

    test('accepts built-in form primitives backed by ht', () async {
      final form = FormData()
        ..append('name', const Multipart.text('oxy'))
        ..append(
          'file',
          Multipart.blob(Blob(['hello'], 'text/plain'), 'a.txt'),
        );
      final body = Body(form);

      expect(body.replayable, isTrue);
      expect(body.contentType, startsWith('multipart/form-data; boundary='));
      expect(body.size, greaterThan(0));

      final boundary = body.contentType!.split('boundary=').last;
      final text = utf8.decode(await body.clone().bytes());
      expect(text, startsWith('--$boundary\r\n'));
      expect(text, endsWith('--$boundary--\r\n'));
      expect(text, contains('name="name"'));
      expect(text, contains('oxy'));
      expect(text, contains('filename="a.txt"'));
      expect(utf8.decode(await body.clone().bytes()), text);
    });

    test('treats Blob and File bodies as streaming file-like bodies', () async {
      final body = Body(Blob(['hello'], 'text/plain'));
      final fileBody = Body(File(['file'], 'a.txt', type: 'text/plain'));

      expect(body.replayable, isTrue);
      expect(body.size, 5);
      expect(body.contentType, 'text/plain');
      expect(await body.clone().text(), 'hello');
      expect(await body.clone().text(), 'hello');

      expect(fileBody.replayable, isTrue);
      expect(fileBody.size, 4);
      expect(fileBody.contentType, 'text/plain');
      expect(await fileBody.clone().text(), 'file');
      expect(await fileBody.clone().text(), 'file');
    });

    test('accepts URLSearchParams as replayable form body', () async {
      final params = URLSearchParams({'q': 'oxy', 'page': '1'});
      final body = Body(params);

      expect(
        body.contentType,
        'application/x-www-form-urlencoded;charset=UTF-8',
      );
      expect(await body.clone().text(), 'q=oxy&page=1');
      expect(await body.clone().text(), 'q=oxy&page=1');
    });

    test('keeps JSON request bodies on the buffered web upload path', () async {
      final body = internal.requestJsonBody({'ok': true});

      expect(body.contentType, 'application/json; charset=utf-8');
      expect(body.size, 11);
      expect(internal.streamsRequestBody(body), isFalse);
      expect(await body.clone().text(), '{"ok":true}');
    });

    test('accepts ht Body as replayable upstream body', () async {
      final upstream = ht.Body('hello');
      final body = Body(upstream);

      expect(body.replayable, isTrue);
      expect(body.size, 5);
      expect(body.contentType, 'text/plain;charset=UTF-8');
      expect(await body.clone().text(), 'hello');
      expect(await body.clone().text(), 'hello');
      expect(upstream.bodyUsed, isFalse);
    });

    test('accepts stream-backed ht Body through clone semantics', () async {
      final upstream = ht.Body(
        Stream<List<int>>.fromIterable([
          utf8.encode('hello '),
          utf8.encode('stream'),
        ]),
      );
      final body = Body(upstream);

      expect(body.replayable, isTrue);
      expect(() => body.size, throwsUnsupportedError);
      expect(await body.clone().text(), 'hello stream');
      expect(await body.clone().text(), 'hello stream');
    });

    test('accepts ByteBuffer through ht-compatible body input', () async {
      final buffer = Uint8List.fromList([1, 2, 3]).buffer;
      final body = Body(buffer);

      expect(body.replayable, isTrue);
      expect(body.size, 3);
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
