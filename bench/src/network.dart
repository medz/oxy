import 'data.dart';

final benchmarkHeaders = Map<String, String>.fromEntries(headerPairs8);

const jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};

const octetHeaders = <String, String>{
  'content-type': 'application/octet-stream',
};

void checkBenchmarkStatus(int? status) {
  if (status == null || status < 200 || status >= 300) {
    throw StateError('Benchmark server rejected request with HTTP $status.');
  }
}
