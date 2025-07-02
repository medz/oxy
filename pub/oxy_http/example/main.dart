import "package:oxy/oxy.dart";
import "package:oxy_http/oxy_http.dart";

Future<void> main() async {
  final adapter = OxyHttp();
  final client = Oxy(adapter: adapter);
  final res = await client.get(
    "https://github.com/medz/oxy/raw/refs/heads/main/LICENSE",
  );

  print(await res.text());
}
