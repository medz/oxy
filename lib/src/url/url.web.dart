import 'dart:js_interop';

import '../url_search_params/url_search_params.dart' show URLSearchParams;

@JS("URL")
extension type URL._(JSObject _) implements JSObject {
  external static URL? parse(String url, [String? base]);
  external static bool canParse(String url, [String base]);
  external factory URL(String url, [String? base]);

  external String get origin;
  external URLSearchParams get searchParams;

  external String hash;
  external String pathname;
  external String protocol;
  external String host;
  external String hostname;
  external String href;
  external String search;
  external String username;
  external String password;

  @JS("port")
  external String _p;

  int get port => int.tryParse(_p) ?? 0;
  set port(int value) => _p = value.toString();
}
