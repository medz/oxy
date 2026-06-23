import 'package:oxy/oxy.dart';

import 'src/data.dart';
import 'src/network.dart';
import 'src/runner.dart';
import 'src/server.dart';

final oxySuite = BenchmarkSuite('oxy', <BenchmarkCase>[
  AsyncBenchmark(
    group: 'network',
    name: 'get-empty',
    run: () async {
      final response = await _client.get('/empty', headers: benchmarkHeaders);
      checkBenchmarkStatus(response.status);
      consume(await response.bytes());
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'get-json-decode',
    run: () async {
      final response = await _client.get('/json', headers: benchmarkHeaders);
      checkBenchmarkStatus(response.status);
      consume(await response.json<Map<String, Object?>>());
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'get-bytes-64k',
    run: () async {
      final response = await _client.get(
        '/bytes-64k',
        headers: benchmarkHeaders,
      );
      checkBenchmarkStatus(response.status);
      consume(await response.bytes());
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'post-json',
    run: () async {
      final response = await _client.post('/json', json: jsonPayload);
      checkBenchmarkStatus(response.status);
      consume(await response.json<Map<String, Object?>>());
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'post-bytes-64k',
    run: () async {
      final response = await _client.post(
        '/bytes-64k',
        headers: octetHeaders,
        body: largeBytes,
      );
      checkBenchmarkStatus(response.status);
      consume(await response.bytes());
    },
  ),
]);

Client? _clientInstance;

Client get _client {
  return _clientInstance ??= Client(
    ClientOptions(baseUrl: benchmarkServer.baseUri),
  );
}

Future<void> closeOxyBenchmarks() async {
  final client = _clientInstance;
  _clientInstance = null;
  await client?.close();
}
