@TestOn('browser')
library;

import 'dart:convert';

import 'package:oxy/oxy.dart';
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
}
