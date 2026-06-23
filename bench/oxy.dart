import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:ht/ht.dart' as ht;
import 'package:oxy/oxy.dart';

Object? benchmarkBlackHole;

final _smallBytes = Uint8List.fromList(
  List<int>.generate(1024, (index) => index & 0xff, growable: false),
);
final _largeBytes = Uint8List.fromList(
  List<int>.generate(64 * 1024, (index) => index & 0xff, growable: false),
);
final _jsonPayload = <String, Object?>{
  'id': 42,
  'name': 'Oxy',
  'tags': <String>['http', 'middleware', 'body'],
  'active': true,
};
final _jsonText = jsonEncode(_jsonPayload);
final _headerPairs8 = _headerPairs(8);
final _headerPairs32 = _headerPairs(32);
final _request = Request(
  '/users/42',
  headers: _headerPairs8,
  options: const RequestOptions(query: <String, Object?>{'include': 'profile'}),
);
final _putRequest = Request(
  '/users/42',
  method: 'PUT',
  headers: const <String, String>{'content-type': 'application/octet-stream'},
  body: Body(_largeBytes),
);

void main(List<String> args) async {
  final config = _RunConfig.fromArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final selected = _cases
      .where((benchmark) => config.matches(benchmark))
      .toList(growable: false);
  if (selected.isEmpty) {
    throw ArgumentError('No benchmarks matched filter: ${config.filter}');
  }

  final results = <_BenchmarkResult>[];
  for (final benchmark in selected) {
    results.add(await benchmark.measureCase(config));
  }

  if (config.json) {
    print(jsonEncode(_jsonReport(config, results)));
  } else {
    _printReport(config, results);
  }
}

final _cases = <_BenchmarkCase>[
  _SyncBenchmark(
    group: 'headers',
    name: 'create-8',
    run: () {
      _consume(Headers(_headerPairs8));
    },
  ),
  _SyncBenchmark(
    group: 'headers',
    name: 'create-32',
    run: () {
      _consume(Headers(_headerPairs32));
    },
  ),
  _SyncBenchmark(
    group: 'headers',
    name: 'iterate-32',
    run: () {
      _consume(Headers(_headerPairs32).toList(growable: false));
    },
  ),
  _SyncBenchmark(
    group: 'request',
    name: 'construct-get',
    run: () {
      _consume(Request('/users/42', headers: _headerPairs8));
    },
  ),
  _SyncBenchmark(
    group: 'request',
    name: 'copy-with-headers',
    run: () {
      _consume(_request.copyWith(headers: _headerPairs32));
    },
  ),
  _SyncBenchmark(
    group: 'body',
    name: 'construct-string',
    run: () {
      _consume(Body(_jsonText));
    },
  ),
  _SyncBenchmark(
    group: 'body',
    name: 'construct-upstream-ht-body',
    run: () {
      _consume(Body(ht.Body(_largeBytes)));
    },
  ),
  _SyncBenchmark(
    group: 'body',
    name: 'clone-bytes',
    run: () {
      _consume(Body(_largeBytes).clone());
    },
  ),
  _AsyncBenchmark(
    group: 'body',
    name: 'bytes-1k',
    run: () async {
      _consume(await Body(_smallBytes).bytes());
    },
  ),
  _AsyncBenchmark(
    group: 'response',
    name: 'bytes-1k',
    run: () async {
      _consume(await Response.bytes(_smallBytes).bytes());
    },
  ),
  _AsyncBenchmark(
    group: 'response',
    name: 'json-decode',
    run: () async {
      _consume(await Response.json(_jsonPayload).json<Map<String, Object?>>());
    },
  ),
  _AsyncBenchmark(
    group: 'client',
    name: 'send-no-middleware',
    run: () async {
      _consume(await _plainClient.send(_request));
    },
  ),
  _AsyncBenchmark(
    group: 'client',
    name: 'request-json-body',
    run: () async {
      _consume(await _plainClient.post('/users', json: _jsonPayload));
    },
  ),
  _AsyncBenchmark(
    group: 'client',
    name: 'send-5-middleware',
    run: () async {
      _consume(await _middlewareClient.send(_request));
    },
  ),
  _AsyncBenchmark(
    group: 'client',
    name: 'retry-replayable-body',
    run: () async {
      _consume(await _retryClient.send(_putRequest));
    },
  ),
];

final _plainClient = Client(
  ClientOptions(
    baseUrl: Uri.parse('https://example.test'),
    transport: const _StaticTransport(),
  ),
);
final _middlewareClient = Client(
  ClientOptions(
    baseUrl: Uri.parse('https://example.test'),
    transport: const _StaticTransport(),
    middleware: List<Middleware>.filled(5, const _NoopMiddleware()),
  ),
);
final _retryClient = Client(
  ClientOptions(
    baseUrl: Uri.parse('https://example.test'),
    transport: const _RetryTransport(),
    retryPolicy: const RetryPolicy(
      maxRetries: 2,
      idempotentMethodsOnly: false,
      baseDelay: Duration.zero,
      maxDelay: Duration.zero,
      jitterRatio: 0,
    ),
  ),
);

List<MapEntry<String, String>> _headerPairs(int count) {
  return List<MapEntry<String, String>>.generate(
    count,
    (index) => MapEntry('x-oxy-$index', 'value-$index'),
    growable: false,
  );
}

void _consume(Object? value) {
  benchmarkBlackHole = value;
}

abstract interface class _BenchmarkCase {
  String get group;
  String get name;
  Future<_BenchmarkResult> measureCase(_RunConfig config);
}

final class _SyncBenchmark extends BenchmarkBase implements _BenchmarkCase {
  _SyncBenchmark({
    required this.group,
    required String name,
    required void Function() run,
  }) : _run = run,
       super(name);

  @override
  final String group;
  final void Function() _run;

  @override
  void run() => _run();

  @override
  void exercise() => run();

  @override
  Future<_BenchmarkResult> measureCase(_RunConfig config) async {
    setup();
    try {
      BenchmarkBase.measureFor(warmup, config.warmupMillis);
      final runtimeMicros = BenchmarkBase.measureFor(
        exercise,
        config.measureMillis,
      );
      return _BenchmarkResult(
        group: group,
        name: name,
        runtimeMicros: runtimeMicros,
      );
    } finally {
      teardown();
    }
  }
}

final class _AsyncBenchmark extends AsyncBenchmarkBase
    implements _BenchmarkCase {
  _AsyncBenchmark({
    required this.group,
    required String name,
    required Future<void> Function() run,
  }) : _run = run,
       super(name);

  @override
  final String group;
  final Future<void> Function() _run;

  @override
  Future<void> run() => _run();

  @override
  Future<_BenchmarkResult> measureCase(_RunConfig config) async {
    await setup();
    try {
      await AsyncBenchmarkBase.measureFor(warmup, config.warmupMillis);
      final runtimeMicros = await AsyncBenchmarkBase.measureFor(
        exercise,
        config.measureMillis,
      );
      return _BenchmarkResult(
        group: group,
        name: name,
        runtimeMicros: runtimeMicros,
      );
    } finally {
      await teardown();
    }
  }
}

final class _BenchmarkResult {
  const _BenchmarkResult({
    required this.group,
    required this.name,
    required this.runtimeMicros,
  });

  final String group;
  final String name;
  final double runtimeMicros;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'group': group,
      'name': name,
      'runtimeMicros': runtimeMicros,
    };
  }
}

final class _RunConfig {
  const _RunConfig({
    required this.json,
    required this.quick,
    required this.filter,
    required this.showHelp,
  });

  factory _RunConfig.fromArgs(List<String> args) {
    return _RunConfig(
      json: args.contains('--json'),
      quick: args.contains('--quick'),
      filter: _optionValue(args, '--filter='),
      showHelp: args.contains('--help') || args.contains('-h'),
    );
  }

  final bool json;
  final bool quick;
  final String? filter;
  final bool showHelp;

  int get warmupMillis => quick ? 30 : 100;
  int get measureMillis => quick ? 150 : 2000;

  bool matches(_BenchmarkCase benchmark) {
    final filter = this.filter;
    if (filter == null || filter.isEmpty) {
      return true;
    }
    return '${benchmark.group}.${benchmark.name}'.contains(filter);
  }
}

String? _optionValue(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
}

Map<String, Object?> _jsonReport(
  _RunConfig config,
  List<_BenchmarkResult> results,
) {
  return <String, Object?>{
    'runner': 'benchmark_harness',
    'mode': config.quick ? 'quick' : 'full',
    'unit': 'microseconds',
    'warmupMillis': config.warmupMillis,
    'measureMillis': config.measureMillis,
    'filter': config.filter,
    'benchmarks': results.map((result) => result.toJson()).toList(),
  };
}

void _printReport(_RunConfig config, List<_BenchmarkResult> results) {
  print('Oxy benchmarks (${config.quick ? 'quick' : 'full'})');
  print('unit: microseconds per run');
  print('');
  for (final result in results) {
    final label = '${result.group}.${result.name}'.padRight(34);
    print('$label ${result.runtimeMicros.toStringAsFixed(3)}');
  }
}

void _printUsage() {
  print('Usage: dart bench/oxy.dart [--quick] [--json] [--filter=<text>]');
  print('');
  print('Examples:');
  print('  dart bench/oxy.dart --quick');
  print('  dart bench/oxy.dart --json --filter=body');
}

final class _StaticTransport implements Transport {
  const _StaticTransport();

  @override
  PlatformCapability get capability => PlatformCapability.test;

  @override
  Future<void> close() => Future<void>.value();

  @override
  Future<Response> send(Request request, Context context) {
    return Future<Response>.value(Response.bytes(const <int>[]));
  }
}

final class _RetryTransport implements Transport {
  const _RetryTransport();

  @override
  PlatformCapability get capability => PlatformCapability.test;

  @override
  Future<void> close() => Future<void>.value();

  @override
  Future<Response> send(Request request, Context context) {
    final status = context.attempt < 2 ? 503 : 200;
    return Future<Response>.value(
      Response.bytes(const <int>[], status: status),
    );
  }
}

final class _NoopMiddleware
    implements
        RequestTransformer,
        AttemptTransformer,
        AttemptResponseHandler,
        FinalResponseHandler,
        FinalFinallyHandler {
  const _NoopMiddleware();

  @override
  Request onRequest(Request request, Context context) => request;

  @override
  Request onAttempt(Request request, Context context) => request;

  @override
  Response onAttemptResponse(
    Request request,
    Response response,
    Context context,
  ) {
    return response;
  }

  @override
  Response onResponse(Request request, Response response, Context context) {
    return response;
  }

  @override
  void onFinally(Request request, Context context) {}
}
