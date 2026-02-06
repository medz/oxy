import 'package:oxy/oxy.dart';

Future<void> main() async {
  final form = FormData()
    ..append('key', 'Value')
    ..append('file', Blob.text('hello from oxy'), filename: 'hello.txt');

  final res = await oxy.post('https://httpbin.org/post', body: form);

  print(await res.text());
}
