import 'package:oxy/oxy.dart';

Future<void> main() async {
  final client = Client(
    ClientOptions(baseUrl: Uri.parse('https://httpbin.org')),
  );

  try {
    final response = await client.post('/post', json: {'name': 'oxy'});
    final payload = await response.json<Map<String, Object?>>();
    print(payload['json']);
  } finally {
    await client.close();
  }
}
