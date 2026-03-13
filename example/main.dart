import 'package:oxy/oxy.dart';

Future<void> main() async {
  final form = FormData()
    ..append('key', const Multipart.text('Value'))
    ..append(
      'file',
      Multipart.blob(Blob(['hello from oxy'], 'text/plain'), 'hello.txt'),
    );

  final res = await oxy.post('https://httpbin.org/post', body: form);

  print(await res.text());
}
