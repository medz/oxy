// import 'package:oxy/oxy.dart';

void main() {
  final [a] = ''.split(':');
  print(a);
  // print(b);
  final b = Uri.parse("http://a.com");
  print(b.origin);
}

// URL {
//   href: "https://name:pwd@developer.mozilla.org:8080/zh-CN/docs/Web/API/URL/href?a=1#222",
//   origin: "https://developer.mozilla.org:8080",
//   protocol: "https:",
//   username: "name",
//   password: "pwd",
//   host: "developer.mozilla.org:8080",
//   hostname: "developer.mozilla.org",
//   port: "8080",
//   pathname: "/zh-CN/docs/Web/API/URL/href",
//   hash: "#222",
//   search: "?a=1",
//   searchParams: URLSearchParams {
//     "a": "1",
//   },
//   toJSON: [Function: toJSON],
//   toString: [Function: toString],
// }
