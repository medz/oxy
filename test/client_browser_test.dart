@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:ht/ht.dart' as ht;
import 'package:oxy/oxy.dart';
import 'package:oxy/src/transport/transport.web.dart' as web;
import 'package:oxy/src/transport/web_stream_utils.dart';
import 'package:test/test.dart';

void main() {
  test('Client uses browser fetch transport for data URLs', () async {
    final url = Uri.dataFromString(
      jsonEncode({'ok': true}),
      mimeType: 'application/json',
      encoding: utf8,
    );

    final response = await Client().get(url);

    expect(response.status, 200);
    expect(await response.json<Map<String, Object?>>(), {'ok': true});
  });

  test('browser transport rejects custom redirect limits', () async {
    final url = Uri.dataFromString('ok', mimeType: 'text/plain');
    final client = Client(
      const ClientOptions(
        redirectPolicy: RedirectPolicy(
          mode: RedirectMode.follow,
          maxRedirects: 1,
        ),
      ),
    );

    await expectLater(client.get(url), throwsA(isA<PolicyError>()));
  });

  test('web transport buffers uploads when fetch streams are unsupported', () {
    final body = Body(Blob(['hello'], 'text/plain'));
    final transport = web.WebTransport();

    expect(
      transport.shouldStreamRequestBody(body, requestStreamsSupported: true),
      isTrue,
    );
    expect(
      transport.shouldStreamRequestBody(body, requestStreamsSupported: false),
      isFalse,
    );
  });

  test('web transport preserves wrapped ht Body upload streams', () {
    final body = Body(ht.Body(Blob(['hello'], 'text/plain')));
    final transport = web.WebTransport();

    expect(
      transport.shouldStreamRequestBody(body, requestStreamsSupported: true),
      isTrue,
    );
  });

  test('web response stream read failures become NetworkError', () async {
    void start(ReadableByteStreamController controller) {
      controller.error('broken'.toJS);
    }

    final stream = ReadableStream(
      UnderlyingSource(type: 'bytes', start: start.toJS),
    );

    await expectLater(
      toDartStream(
        stream,
        request: Request('https://example.com/broken'),
      ).toList(),
      throwsA(
        isA<NetworkError>()
            .having((error) => error.sent, 'sent', isTrue)
            .having((error) => error.request?.uri.host, 'host', 'example.com'),
      ),
    );
  });
}
