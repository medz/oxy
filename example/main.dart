import 'package:oxy/src/request/request.web.dart';
import 'package:oxy/src/url/url.web.dart';

create() {
  return Request(RequestInfo.url(URL("https://x.com")));
}

void main() {
  create();
  final req = create();

  print(req is Request);
}
