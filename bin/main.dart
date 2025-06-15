import 'package:oxy/src/request/request.web.dart';
import 'package:oxy/src/url/url.web.dart';

void main() {
  final req = Request(RequestInfo.url(URL("https://x.com")));
  print(req);
}
