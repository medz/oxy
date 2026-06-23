import 'package:dio/dio.dart' as dio;

import 'src/data.dart';
import 'src/network.dart';
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
      checkBenchmarkStatus(response.statusCode);
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
      checkBenchmarkStatus(response.statusCode);
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
      checkBenchmarkStatus(response.statusCode);
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
      checkBenchmarkStatus(response.statusCode);
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
      checkBenchmarkStatus(response.statusCode);
      consume(response.statusCode);
    },
  ),
]);

final _headersOptions = dio.Options(headers: benchmarkHeaders);
final _jsonOptions = dio.Options(headers: jsonHeaders);
final _bytesOptions = dio.Options(
  headers: benchmarkHeaders,
  responseType: dio.ResponseType.bytes,
);
final _postBytesOptions = dio.Options(
  headers: octetHeaders,
  responseType: dio.ResponseType.plain,
);

dio.Dio? _clientInstance;

dio.Dio get _client {
  return _clientInstance ??= dio.Dio(
    dio.BaseOptions(
      baseUrl: benchmarkServer.baseUri.toString(),
      responseType: dio.ResponseType.json,
    ),
  );
}

Future<void> closeDioBenchmarks() async {
  _clientInstance?.close(force: true);
  _clientInstance = null;
}
