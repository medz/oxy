import 'dart:async';
import 'dart:convert';

import 'package:benchmark_harness/benchmark_harness.dart';

Object? benchmarkBlackHole;

void consume(Object? value) {
  benchmarkBlackHole = value;
}

final class BenchmarkSuite {
  const BenchmarkSuite(this.name, this.cases);

  final String name;
  final List<BenchmarkCase> cases;
}

abstract interface class BenchmarkCase {
  String get group;
  String get name;
  Future<BenchmarkResult> measureCase(RunConfig config);
}

final class SyncBenchmark extends BenchmarkBase implements BenchmarkCase {
  SyncBenchmark({
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
  Future<BenchmarkResult> measureCase(RunConfig config) async {
    setup();
    try {
      BenchmarkBase.measureFor(warmup, config.warmupMillis);
      final runtimeMicros = BenchmarkBase.measureFor(
        exercise,
        config.measureMillis,
      );
      return BenchmarkResult(
        group: group,
        name: name,
        runtimeMicros: runtimeMicros,
      );
    } finally {
      teardown();
    }
  }
}

final class AsyncBenchmark extends AsyncBenchmarkBase implements BenchmarkCase {
  AsyncBenchmark({
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
  Future<BenchmarkResult> measureCase(RunConfig config) async {
    await setup();
    try {
      await AsyncBenchmarkBase.measureFor(warmup, config.warmupMillis);
      final runtimeMicros = await AsyncBenchmarkBase.measureFor(
        exercise,
        config.measureMillis,
      );
      return BenchmarkResult(
        group: group,
        name: name,
        runtimeMicros: runtimeMicros,
      );
    } finally {
      await teardown();
    }
  }
}

final class BenchmarkResult {
  const BenchmarkResult({
    this.suite = '',
    required this.group,
    required this.name,
    required this.runtimeMicros,
  });

  final String suite;
  final String group;
  final String name;
  final double runtimeMicros;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'suite': suite,
      'group': group,
      'name': name,
      'runtimeMicros': runtimeMicros,
    };
  }
}

final class RunConfig {
  const RunConfig({
    required this.json,
    required this.quick,
    required this.suite,
    required this.filter,
    required this.showHelp,
  });

  factory RunConfig.fromArgs(List<String> args) {
    return RunConfig(
      json: args.contains('--json'),
      quick: args.contains('--quick'),
      suite: _optionValue(args, '--suite=') ?? 'baseline,oxy',
      filter: _optionValue(args, '--filter='),
      showHelp: args.contains('--help') || args.contains('-h'),
    );
  }

  final bool json;
  final bool quick;
  final String suite;
  final String? filter;
  final bool showHelp;

  int get warmupMillis => quick ? 30 : 100;
  int get measureMillis => quick ? 150 : 2000;

  bool matches(BenchmarkSuite suite, BenchmarkCase benchmark) {
    final filter = this.filter;
    if (filter == null || filter.isEmpty) {
      return true;
    }
    return '${suite.name}.${benchmark.group}.${benchmark.name}'.contains(
      filter,
    );
  }
}

Future<List<BenchmarkResult>> measureSuites(
  RunConfig config,
  Iterable<BenchmarkSuite> suites,
) async {
  final results = <BenchmarkResult>[];
  for (final suite in suites) {
    final selected = suite.cases.where((benchmark) {
      return config.matches(suite, benchmark);
    });
    for (final benchmark in selected) {
      final result = await benchmark.measureCase(config);
      results.add(
        BenchmarkResult(
          suite: suite.name,
          group: result.group,
          name: result.name,
          runtimeMicros: result.runtimeMicros,
        ),
      );
    }
  }
  return results;
}

void printReport(RunConfig config, List<BenchmarkResult> results) {
  if (config.json) {
    print(jsonEncode(jsonReport(config, results)));
    return;
  }

  print('Oxy benchmarks (${config.quick ? 'quick' : 'full'})');
  print('unit: microseconds per run');
  print('');
  for (final result in results) {
    final label = '${result.suite}.${result.group}.${result.name}'.padRight(42);
    print('$label ${result.runtimeMicros.toStringAsFixed(3)}');
  }
}

Map<String, Object?> jsonReport(
  RunConfig config,
  List<BenchmarkResult> results,
) {
  return <String, Object?>{
    'runner': 'benchmark_harness',
    'mode': config.quick ? 'quick' : 'full',
    'unit': 'microseconds',
    'suite': config.suite,
    'filter': config.filter,
    'warmupMillis': config.warmupMillis,
    'measureMillis': config.measureMillis,
    'benchmarks': results.map((result) => result.toJson()).toList(),
  };
}

String? _optionValue(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
}
