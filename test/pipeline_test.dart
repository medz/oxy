import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';
import 'package:test/test.dart';

final class HeaderMiddleware implements Middleware {
  HeaderMiddleware(this.name, this.value, this.events);

  final String name;
  final String value;
  final List<String> events;

  @override
  Future<Response> intercept(Request request, Context context, Next next) {
    events.add('$name:${context.attempt}');
    return next(request.withHeader(name, value), context);
  }
}

void main() {
  test(
    'runs application middleware once and network middleware per attempt',
    () async {
      var calls = 0;
      final events = <String>[];
      final transport = MockTransport((request, context) async {
        calls += 1;
        if (calls == 1) {
          return Response.text('retry', status: 503);
        }
        return Response.json({
          'app': request.headers.get('x-app'),
          'net': request.headers.get('x-net'),
          'attempt': context.attempt,
        });
      });

      final client = Client(
        ClientOptions(
          baseUrl: Uri.parse('https://example.com'),
          transport: transport,
          middleware: [HeaderMiddleware('x-app', '1', events)],
          networkMiddleware: [HeaderMiddleware('x-net', '1', events)],
        ),
      );

      final response = await client.get('/resource');
      final payload = await response.json<Map<String, Object?>>();

      expect(calls, 2);
      expect(events, ['x-app:0', 'x-net:0', 'x-net:1']);
      expect(payload['app'], '1');
      expect(payload['net'], '1');
      expect(payload['attempt'], 1);
    },
  );

  test('uses typed attributes instead of string extras', () async {
    const key = AttributeKey<String>('tenant');
    late String? tenant;

    final transport = MockTransport((request, context) async {
      tenant = context.attribute(key);
      return Response.text('ok');
    });

    final client = Client(
      ClientOptions(
        transport: transport,
        attributes: const Attributes().set(key, 'pa'),
      ),
    );

    await client.get('https://example.com');
    expect(tenant, 'pa');
  });

  test('sendResult is the single no-throw client entry', () async {
    final client = Client(
      ClientOptions(
        retryPolicy: const RetryPolicy(maxRetries: 0),
        transport: MockTransport((request, context) async {
          throw const NetworkError('down');
        }),
      ),
    );

    final result = await client.sendResult(Request('https://example.com'));
    expect(result.isFailure, isTrue);
    expect(result.error, isA<NetworkError>());
  });
}
