import 'package:oxy/oxy.dart';

final client = Oxy(baseURL: Uri.parse('https://webhook.site'));

Future<void> main() async {
  final res = await client.get('/7fa9b9f4-439d-4017-9382-08ac4baf9a4d');
  print(res.ok);
}
