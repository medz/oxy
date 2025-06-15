import 'package:oxy/oxy.dart';
// import 'package:oxy/src/headers/headers.web.dart';

void main() {
  final headers = URL("https://a.com");
  headers.searchParams.set("a", "X");

  print(headers.search);
}
