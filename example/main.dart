import 'package:oxy/oxy.dart';

Future<void> main() async {
  final response = await fetch('https://httpbin.org/get');
  final payload = await response.json<Map<String, Object?>>();

  print(payload['url']);
}
