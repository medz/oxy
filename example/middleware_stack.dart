import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';

Future<void> main() async {
  final logs = <String>[];
  final client = Client(
    ClientOptions(
      baseUrl: Uri.parse('https://api.example.com'),
      middleware: [
        RequestIdMiddleware(requestIdProvider: (_, _) => 'request-1'),
        AuthMiddleware.staticToken('secret'),
        CookieMiddleware(),
        CacheMiddleware(
          keyBuilder: (request, context) {
            return '${request.method} ${request.uri}';
          },
        ),
        LoggingMiddleware(printer: logs.add),
      ],
      transport: MockTransport((request, context) async {
        return Response.json(
          {'ok': true},
          headers: {
            'cache-control': 'max-age=60',
            'set-cookie': 'sid=abc; Path=/',
          },
        );
      }),
    ),
  );

  try {
    final first = await client.get('/profile');
    final second = await client.get('/profile');

    print(first.fromCache);
    print(second.fromCache);
    print(logs.length);
  } finally {
    await client.close();
  }
}
