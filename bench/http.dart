import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'src/data.dart';
import 'src/runner.dart';

final httpSuite = BenchmarkSuite('http', <BenchmarkCase>[
  SyncBenchmark(
    group: 'request',
    name: 'construct-get',
    run: () {
      consume(http.Request('GET', _uri)..headers.addAll(_headers8));
    },
  ),
  SyncBenchmark(
    group: 'request',
    name: 'construct-post-json',
    run: () {
      consume(
        http.Request('POST', _uri)
          ..headers.addAll(_jsonHeaders)
          ..bodyBytes = utf8.encode(jsonText),
      );
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'send-no-middleware',
    run: () async {
      consume(await _client.get(_uri, headers: _headers8));
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'post-json-body',
    run: () async {
      consume(await _client.post(_uri, headers: _jsonHeaders, body: jsonText));
    },
  ),
  AsyncBenchmark(
    group: 'response',
    name: 'bytes-1k',
    run: () async {
      final response = await _client.get(_bytesUri);
      consume(response.bodyBytes);
    },
  ),
  AsyncBenchmark(
    group: 'response',
    name: 'json-decode',
    run: () async {
      final response = await _client.get(_jsonUri);
      consume(jsonDecode(response.body));
    },
  ),
]);

final _uri = Uri.parse('https://example.test/users/42');
final _jsonUri = Uri.parse('https://example.test/json');
final _bytesUri = Uri.parse('https://example.test/bytes');
final _headers8 = Map<String, String>.fromEntries(headerPairs8);
const _jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};

final _client = http_testing.MockClient.streaming((request, bodyStream) async {
  await bodyStream.drain<void>();
  if (request.url == _jsonUri) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonText)),
      200,
      headers: _jsonHeaders,
    );
  }
  if (request.url == _bytesUri) {
    return http.StreamedResponse(
      Stream<List<int>>.value(smallBytes),
      200,
      contentLength: smallBytes.length,
    );
  }
  return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
});
