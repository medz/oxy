import 'package:oxy/oxy.dart';
import 'package:oxy_dio/oxy_dio.dart';

void main() async {
  final adapter = OxyDio();
  final oxy = Oxy(adapter: adapter);
  final res = await oxy.get(
    "https://github.com/medz/oxy/raw/refs/heads/main/LICENSE",
  );

  print(await res.text());
}
