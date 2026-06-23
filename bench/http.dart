import 'dart:convert';

import 'package:http/http.dart' as http;

import 'src/data.dart';
import 'src/network.dart';
import 'src/runner.dart';
import 'src/server.dart';

final httpSuite = BenchmarkSuite('http', <BenchmarkCase>[
  AsyncBenchmark(
    group: 'network',
    name: 'get-empty',
    run: () async {
      final response = await _client.get(
        _uri('/empty'),
        headers: benchmarkHeaders,
      );
      checkBenchmarkStatus(response.statusCode);
      consume(response.statusCode);
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'get-json-decode',
    run: () async {
      final response = await _client.get(
        _uri('/json'),
        headers: benchmarkHeaders,
      );
      checkBenchmarkStatus(response.statusCode);
      consume(jsonDecode(response.body));
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'get-bytes-64k',
    run: () async {
      final response = await _client.get(
        _uri('/bytes-64k'),
        headers: benchmarkHeaders,
      );
      checkBenchmarkStatus(response.statusCode);
      consume(response.bodyBytes);
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'post-json',
    run: () async {
      final response = await _client.post(
        _uri('/json'),
        headers: jsonHeaders,
        body: jsonText,
      );
      checkBenchmarkStatus(response.statusCode);
      consume(jsonDecode(response.body));
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'post-bytes-64k',
    run: () async {
      final response = await _client.post(
        _uri('/bytes-64k'),
        headers: octetHeaders,
        body: largeBytes,
      );
      checkBenchmarkStatus(response.statusCode);
      consume(response.statusCode);
    },
  ),
]);

http.Client? _clientInstance;

http.Client get _client {
  return _clientInstance ??= http.Client();
}

Uri _uri(String path) => benchmarkServer.uri(path);

Future<void> closeHttpBenchmarks() async {
  _clientInstance?.close();
  _clientInstance = null;
}
