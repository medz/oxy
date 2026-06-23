import 'package:dio/dio.dart' as dio;

import 'src/data.dart';
import 'src/runner.dart';
import 'src/server.dart';

final dioSuite = BenchmarkSuite('dio', <BenchmarkCase>[
  AsyncBenchmark(
    group: 'network',
    name: 'get-empty',
    run: () async {
      final response = await _client.get<Object?>(
        '/empty',
        options: _headersOptions,
      );
      consume(response.statusCode);
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'get-json-decode',
    run: () async {
      final response = await _client.get<Map<String, Object?>>(
        '/json',
        options: _headersOptions,
      );
      consume(response.data);
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'get-bytes-64k',
    run: () async {
      final response = await _client.get<List<int>>(
        '/bytes-64k',
        options: _bytesOptions,
      );
      consume(response.data);
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'post-json',
    run: () async {
      final response = await _client.post<Map<String, Object?>>(
        '/json',
        data: jsonPayload,
        options: _jsonOptions,
      );
      consume(response.data);
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'post-bytes-64k',
    run: () async {
      final response = await _client.post<Object?>(
        '/bytes-64k',
        data: largeBytes,
        options: _postBytesOptions,
      );
      consume(response.statusCode);
    },
  ),
]);

final _headers8 = Map<String, String>.fromEntries(headerPairs8);
const _jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};
const _octetHeaders = <String, String>{
  'content-type': 'application/octet-stream',
};
final _headersOptions = dio.Options(headers: _headers8);
final _jsonOptions = dio.Options(headers: _jsonHeaders);
final _bytesOptions = dio.Options(responseType: dio.ResponseType.bytes);
final _postBytesOptions = dio.Options(
  headers: _octetHeaders,
  responseType: dio.ResponseType.plain,
);

dio.Dio? _clientInstance;

dio.Dio get _client {
  return _clientInstance ??= dio.Dio(
    dio.BaseOptions(
      baseUrl: benchmarkServer.baseUri.toString(),
      responseType: dio.ResponseType.json,
      validateStatus: (_) => true,
    ),
  );
}

Future<void> closeDioBenchmarks() async {
  _clientInstance?.close(force: true);
  _clientInstance = null;
}
