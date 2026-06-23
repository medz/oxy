import 'baseline.dart';
import 'dio.dart' as dio_suite;
import 'http.dart' as http_suite;
import 'oxy.dart';
import 'src/runner.dart';

final _suites = <String, BenchmarkSuite>{
  baselineSuite.name: baselineSuite,
  oxySuite.name: oxySuite,
  http_suite.httpSuite.name: http_suite.httpSuite,
  dio_suite.dioSuite.name: dio_suite.dioSuite,
};

void main(List<String> args) async {
  final config = RunConfig.fromArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final suites = _selectSuites(config.suite);
  final results = await measureSuites(config, suites);
  if (results.isEmpty) {
    throw ArgumentError(
      'No benchmarks matched suite `${config.suite}`'
      '${config.filter == null ? '' : ' and filter `${config.filter}`'}.',
    );
  }

  printReport(config, results);
}

List<BenchmarkSuite> _selectSuites(String value) {
  final selected = <BenchmarkSuite>[];
  for (final name in value.split(',')) {
    switch (name.trim()) {
      case '':
        break;
      case 'all':
        selected.addAll(_suites.values);
      case 'clients':
        selected.addAll(<BenchmarkSuite>[
          oxySuite,
          http_suite.httpSuite,
          dio_suite.dioSuite,
        ]);
      case final suiteName:
        final suite = _suites[suiteName];
        if (suite == null) {
          throw ArgumentError.value(suiteName, 'suite', 'Unknown suite');
        }
        selected.add(suite);
    }
  }
  return selected.toSet().toList(growable: false);
}

void _printUsage() {
  print('Usage: dart bench/main.dart [--quick] [--json] [--suite=<name>] ');
  print('                           [--filter=<text>]');
  print('');
  print('Suites: baseline, oxy, http, dio, clients, all');
  print('');
  print('Examples:');
  print('  dart bench/main.dart --quick');
  print('  dart bench/main.dart --suite=clients --json');
  print('  dart bench/main.dart --suite=oxy --filter=body');
}
