import 'dart:convert';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;

import 'src/data.dart';
import 'src/runner.dart';

final baselineSuite = BenchmarkSuite('baseline', <BenchmarkCase>[
  SyncBenchmark(
    group: 'json',
    name: 'encode',
    run: () {
      consume(jsonEncode(jsonPayload));
    },
  ),
  SyncBenchmark(
    group: 'json',
    name: 'decode',
    run: () {
      consume(jsonDecode(jsonText));
    },
  ),
  SyncBenchmark(
    group: 'bytes',
    name: 'copy-1k',
    run: () {
      consume(Uint8List.fromList(smallBytes));
    },
  ),
  SyncBenchmark(
    group: 'headers',
    name: 'create-8',
    run: () {
      consume(ht.Headers(headerPairs8));
    },
  ),
  SyncBenchmark(
    group: 'headers',
    name: 'create-32',
    run: () {
      consume(ht.Headers(headerPairs32));
    },
  ),
  SyncBenchmark(
    group: 'headers',
    name: 'iterate-32',
    run: () {
      consume(ht.Headers(headerPairs32).toList(growable: false));
    },
  ),
  SyncBenchmark(
    group: 'body',
    name: 'construct-string',
    run: () {
      consume(ht.Body(jsonText));
    },
  ),
  SyncBenchmark(
    group: 'body',
    name: 'clone-bytes',
    run: () {
      consume(ht.Body(largeBytes).clone());
    },
  ),
  AsyncBenchmark(
    group: 'body',
    name: 'bytes-1k',
    run: () async {
      consume(await ht.Body(smallBytes).bytes());
    },
  ),
]);
