import 'package:oxy/oxy.dart';

import 'src/data.dart';
import 'src/runner.dart';
import 'src/server.dart';

final oxySuite = BenchmarkSuite('oxy', <BenchmarkCase>[
  AsyncBenchmark(
    group: 'network',
    name: 'get-empty',
    run: () async {
      final response = await _client.get('/empty');
      consume(await response.bytes());
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'get-json-decode',
    run: () async {
      final response = await _client.get('/json');
      consume(await response.json<Map<String, Object?>>());
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'get-bytes-64k',
    run: () async {
      final response = await _client.get('/bytes-64k');
      consume(await response.bytes());
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'post-json',
    run: () async {
      final response = await _client.post('/json', json: jsonPayload);
      consume(await response.json<Map<String, Object?>>());
    },
  ),
  AsyncBenchmark(
    group: 'network',
    name: 'post-bytes-64k',
    run: () async {
      final response = await _client.post(
        '/bytes-64k',
        headers: _octetHeaders,
        body: largeBytes,
      );
      consume(await response.bytes());
    },
  ),
]);

const _octetHeaders = <String, String>{
  'content-type': 'application/octet-stream',
};

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
