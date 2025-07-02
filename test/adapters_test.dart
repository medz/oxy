@TestOn("vm")
library;

import 'package:oxy/oxy.dart';
import 'package:oxy_http/oxy_http.dart';
import 'package:test/test.dart';

import 'use_adapter_tests.dart';

void main() {
  useAdapterTests("Default", const DefaultAdapter());
  useAdapterTests("`http` package", OxyHttp());
}
