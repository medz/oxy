import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';
import 'package:test/test.dart';

void main() {
  test('default user-agent identifies Oxy without a stale release version', () {
    expect(const ClientOptions().userAgent, 'oxy');
  });

  for (final (name, options, headers, requestOptions, expected) in [
    ('default', const ClientOptions(), null, null, 'oxy'),
    (
      'custom',
      const ClientOptions(userAgent: 'sdk/1.0'),
      null,
      null,
      'sdk/1.0',
    ),
    ('disabled', const ClientOptions(userAgent: ''), null, null, null),
    (
      'default header',
      const ClientOptions(defaultHeaders: {'user-agent': 'app/1.0'}),
      null,
      null,
      'app/1.0',
    ),
    (
      'request header',
      const ClientOptions(userAgent: 'sdk/1.0'),
      {'user-agent': 'app/2.0'},
      null,
      'app/2.0',
    ),
    (
      'request options',
      const ClientOptions(userAgent: 'sdk/1.0'),
      {'user-agent': 'app/2.0'},
      const RequestOptions(headers: {'user-agent': 'request/3.0'}),
      'request/3.0',
    ),
    (
      'copyWith',
      const ClientOptions().copyWith(userAgent: 'copied/1.0'),
      null,
      null,
      'copied/1.0',
    ),
  ]) {
    test('$name user-agent survives request preparation', () async {
      final transport = MockTransport((_, _) async => Response.text('ok'));
      final client = Client(options.copyWith(transport: transport));
      addTearDown(client.close);

      await client.get(
        'https://example.com',
        headers: headers,
        options: requestOptions,
      );

      expect(transport.requests.single.headers.get('user-agent'), expected);
    });
  }
}
