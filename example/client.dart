import 'package:oxy/oxy.dart';

final client = Oxy(OxyConfig(baseUrl: Uri.parse('https://webhook.site')));

Future<void> main() async {
  final res = await client.get('/anything');
  print(res.ok);
}
