@TestOn("vm")
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';
import 'package:oxy_http/oxy_http.dart';

createTestServer() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
  server.listen((request) {
    request.response.write("OK");
    request.response.statusCode = 200;
  });
}

void main() {}
