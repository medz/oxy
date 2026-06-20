import 'package:oxy/oxy.dart';

Future<void> main() async {
  try {
    final response = await fetch('https://httpbin.org/get');
    final payload = await response.json<Map<String, Object?>>();

    print(payload['url']);
  } finally {
    // Close the shared client when a short-lived script is done.
    await client.close();
  }
}
