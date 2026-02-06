@TestOn('browser')
library;

import 'dart:convert';

import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('Oxy client (browser)', () {
    late String textUrl;
    late String jsonUrl;

    setUp(() {
      textUrl = Uri.dataFromString(
        'hello browser',
        mimeType: 'text/plain',
        encoding: utf8,
      ).toString();
      jsonUrl = Uri.dataFromString(
        jsonEncode(<String, Object?>{'ok': true}),
        mimeType: 'application/json',
        encoding: utf8,
      ).toString();
    });

    test('gets text from data URL', () async {
      final client = Oxy();
      final response = await client.get(textUrl);

      expect(response.status, 200);
      expect(await response.text(), 'hello browser');
    });

    test('supports typed decode on browser transport', () async {
      final client = Oxy();

      final decoded = await client.getDecoded<bool>(
        jsonUrl,
        decoder: (value) => (value as Map<String, Object?>)['ok'] as bool,
      );

      expect(decoded, isTrue);
    });

    test('safeGetDecoded returns OxySuccess on browser', () async {
      final client = Oxy();

      final result = await client.safeGetDecoded<bool>(
        jsonUrl,
        decoder: (value) => (value as Map<String, Object?>)['ok'] as bool,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, isTrue);
    });

    test('safeGet captures abort as OxyFailure', () async {
      final client = Oxy();
      final signal = AbortSignal()..abort('cancelled before send');

      final result = await client.safeGet(
        textUrl,
        options: RequestOptions(signal: signal),
      );

      expect(result.isFailure, isTrue);
      expect(result.error, isA<OxyCancelledException>());
    });

    test('reports send and receive progress on browser', () async {
      final client = Oxy();
      final sent = <TransferProgress>[];
      final received = <TransferProgress>[];

      final response = await client.request(
        'GET',
        textUrl,
        onSendProgress: sent.add,
        onReceiveProgress: received.add,
      );
      final text = await response.text();

      expect(text, 'hello browser');
      expect(sent, isNotEmpty);
      expect(sent.first.transferred, 0);
      expect(sent.last.transferred, 0);
      expect(sent.last.total, isNull);
      expect(received, isNotEmpty);
      expect(received.last.transferred, greaterThan(0));
    });
  });
}
