import 'package:oxy/oxy.dart';

void main() {
  final params = URLSearchParams.parse("key=1&a=2");
  params.append('key', 'value');
  params.append('key', '你好');

  print(params.stringify());
  print(params.getAll("key"));
}
