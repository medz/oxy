import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';

Future<void> main() async {
  var calls = 0;
  final client = Client(
    ClientOptions(
      baseUrl: Uri.parse('https://api.example.com'),
      timeoutPolicy: const TimeoutPolicy(total: Duration(seconds: 20)),
      retryPolicy: const RetryPolicy(maxRetries: 1, baseDelay: Duration.zero),
      redirectPolicy: RedirectPolicy.manual,
      transport: MockTransport((request, context) async {
        if (request.uri.path == '/flaky' && calls++ == 0) {
          return Response.text('try again', status: 503);
        }
        if (request.uri.path == '/missing') {
          return Response.text('missing', status: 404);
        }
        return Response.text('ok');
      }),
    ),
  );

  try {
    final retried = await client.get('/flaky');
    print(await retried.text());

    final expected404 = await client.get(
      '/missing',
      options: const RequestOptions(statusPolicy: StatusPolicy.returnResponse),
    );
    print(expected404.status);
  } finally {
    await client.close();
  }
}
