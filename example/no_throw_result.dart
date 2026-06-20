import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';

Future<void> main() async {
  final client = Client(
    ClientOptions(
      baseUrl: Uri.parse('https://api.example.com'),
      transport: MockTransport((request, context) async {
        return Response.text(
          'bad request',
          status: 400,
          statusText: 'Bad Request',
        );
      }),
    ),
  );

  try {
    final result = await client.requestResult('GET', '/health');

    final message = result.fold(
      onSuccess: (response) => 'status ${response.status}',
      onFailure: (error, trace) => 'failed with $error',
    );
    print(message);
  } finally {
    await client.close();
  }
}
