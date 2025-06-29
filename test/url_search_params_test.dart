import 'package:test/test.dart';
import 'package:oxy/src/url_search_params/url_search_params.dart';

void main() {
  group('URLSearchParams', () {
    group('Construction', () {
      test('empty constructor', () {
        final params = URLSearchParams();
        expect(params.size, equals(0));
        expect(params.stringify(), equals(''));
      });

      test('parse empty query', () {
        final params = URLSearchParams.parse('');
        expect(params.size, equals(0));
        expect(params.stringify(), equals(''));
      });

      test('parse query with question mark', () {
        final params = URLSearchParams.parse('?foo=bar&baz=qux');
        expect(params.size, equals(2));
        expect(params.get('foo'), equals('bar'));
        expect(params.get('baz'), equals('qux'));
      });

      test('parse query without question mark', () {
        final params = URLSearchParams.parse('foo=bar&baz=qux');
        expect(params.size, equals(2));
        expect(params.get('foo'), equals('bar'));
        expect(params.get('baz'), equals('qux'));
      });

      test('parse query with multiple question marks', () {
        final params = URLSearchParams.parse('???foo=bar&baz=qux');
        expect(params.size, equals(2));
        expect(params.get('foo'), equals('bar'));
        expect(params.get('baz'), equals('qux'));
      });

      test('parse query with empty parameters', () {
        final params = URLSearchParams.parse('foo=&=bar&baz=qux&');
        expect(params.size, equals(2));
        expect(params.get('foo'), equals(''));
        expect(params.get('baz'), equals('qux'));
        expect(params.has(''), isFalse); // Empty names should be ignored
      });

      test('parse query with no equals sign', () {
        final params = URLSearchParams.parse('foo&bar=baz');
        expect(params.size, equals(2));
        expect(params.get('foo'), equals(''));
        expect(params.get('bar'), equals('baz'));
      });

      test('parse query with encoded characters', () {
        final params = URLSearchParams.parse('foo=hello%20world&bar=%26%3D%3F');
        expect(params.get('foo'), equals('hello world'));
        expect(params.get('bar'), equals('&=?'));
      });

      test('fromMap constructor', () {
        final params = URLSearchParams.fromMap({'foo': 'bar', 'baz': 'qux'});
        expect(params.size, equals(2));
        expect(params.get('foo'), equals('bar'));
        expect(params.get('baz'), equals('qux'));
      });
    });

    group('Basic operations', () {
      late URLSearchParams params;

      setUp(() {
        params = URLSearchParams.parse('foo=bar&baz=qux');
      });

      test('get existing parameter', () {
        expect(params.get('foo'), equals('bar'));
        expect(params.get('baz'), equals('qux'));
      });

      test('get non-existing parameter', () {
        expect(params.get('nonexistent'), isNull);
      });

      test('has existing parameter', () {
        expect(params.has('foo'), isTrue);
        expect(params.has('baz'), isTrue);
      });

      test('has non-existing parameter', () {
        expect(params.has('nonexistent'), isFalse);
      });

      test('has with specific value', () {
        expect(params.has('foo', 'bar'), isTrue);
        expect(params.has('foo', 'baz'), isFalse);
        expect(params.has('nonexistent', 'value'), isFalse);
      });

      test('size property', () {
        expect(params.size, equals(2));
        params.append('new', 'value');
        expect(params.size, equals(3));
      });
    });

    group('Modification operations', () {
      late URLSearchParams params;

      setUp(() {
        params = URLSearchParams();
      });

      test('append single parameter', () {
        params.append('foo', 'bar');
        expect(params.size, equals(1));
        expect(params.get('foo'), equals('bar'));
      });

      test('append multiple values for same parameter', () {
        params.append('foo', 'bar');
        params.append('foo', 'baz');
        expect(params.size, equals(2));
        expect(params.get('foo'), equals('bar')); // First value
        expect(params.getAll('foo'), equals(['bar', 'baz']));
      });

      test('set replaces all values', () {
        params.append('foo', 'bar');
        params.append('foo', 'baz');
        params.set('foo', 'qux');
        expect(params.size, equals(1));
        expect(params.get('foo'), equals('qux'));
        expect(params.getAll('foo'), equals(['qux']));
      });

      test('delete by name only', () {
        params.append('foo', 'bar');
        params.append('foo', 'baz');
        params.append('qux', 'quux');
        params.delete('foo');
        expect(params.size, equals(1));
        expect(params.has('foo'), isFalse);
        expect(params.get('qux'), equals('quux'));
      });

      test('delete by name and value', () {
        params.append('foo', 'bar');
        params.append('foo', 'baz');
        params.delete('foo', 'bar');
        expect(params.size, equals(1));
        expect(params.get('foo'), equals('baz'));
        expect(params.getAll('foo'), equals(['baz']));
      });

      test('delete non-existing parameter', () {
        params.append('foo', 'bar');
        params.delete('nonexistent');
        expect(params.size, equals(1));
        expect(params.get('foo'), equals('bar'));
      });
    });

    group('Iteration', () {
      late URLSearchParams params;

      setUp(() {
        params = URLSearchParams.parse('a=1&b=2&a=3&c=4');
      });

      test('keys() returns unique names in insertion order', () {
        final keys = params.keys().toList();
        expect(keys, equals(['a', 'b', 'c']));
      });

      test('values() returns all values in insertion order', () {
        final values = params.values().toList();
        expect(values, equals(['1', '2', '3', '4']));
      });

      test('entries() returns all entries in insertion order', () {
        final entries = params.entries().toList();
        expect(
          entries,
          equals([
            ['a', '1'],
            ['b', '2'],
            ['a', '3'],
            ['c', '4'],
          ]),
        );
      });

      test('getAll() returns all values for a name', () {
        expect(params.getAll('a'), equals(['1', '3']));
        expect(params.getAll('b'), equals(['2']));
        expect(params.getAll('nonexistent'), equals([]));
      });
    });

    group('Sorting', () {
      test('sort orders parameters by name', () {
        final params = URLSearchParams.parse('z=26&a=1&m=13&a=2');
        params.sort();

        final keys = params.keys().toList();
        expect(keys, equals(['a', 'm', 'z']));

        final entries = params.entries().toList();
        expect(
          entries,
          equals([
            ['a', '1'],
            ['a', '2'],
            ['m', '13'],
            ['z', '26'],
          ]),
        );
      });
    });

    group('String representation', () {
      test('stringify empty parameters', () {
        final params = URLSearchParams();
        expect(params.stringify(), equals(''));
      });

      test('stringify single parameter', () {
        final params = URLSearchParams();
        params.append('foo', 'bar');
        expect(params.stringify(), equals('foo=bar'));
      });

      test('stringify multiple parameters', () {
        final params = URLSearchParams.parse('foo=bar&baz=qux');
        expect(params.stringify(), equals('foo=bar&baz=qux'));
      });

      test('stringify with special characters', () {
        final params = URLSearchParams();
        params.append('foo', 'hello world');
        params.append('bar', '&=?');
        final result = params.stringify();
        expect(result, contains('foo=hello%20world'));
        expect(result, contains('bar=%26%3D%3F'));
      });

      test('stringify method works correctly', () {
        final params = URLSearchParams.parse('foo=bar&baz=qux');
        expect(params.stringify(), equals('foo=bar&baz=qux'));
      });
    });

    group('Edge cases', () {
      test('parameter name with empty value', () {
        final params = URLSearchParams.parse('foo=');
        expect(params.get('foo'), equals(''));
        expect(params.has('foo'), isTrue);
      });

      test('parameter without equals sign', () {
        final params = URLSearchParams.parse('foo');
        expect(params.get('foo'), equals(''));
        expect(params.has('foo'), isTrue);
      });

      test('multiple equals signs', () {
        final params = URLSearchParams.parse('foo=bar=baz');
        expect(params.get('foo'), equals('bar=baz'));
      });

      test('encoded equals and ampersand', () {
        final params = URLSearchParams.parse('foo%3Dbar=baz%26qux');
        expect(params.get('foo=bar'), equals('baz&qux'));
      });

      test('empty parameter names are ignored', () {
        final params = URLSearchParams.parse('=value&foo=bar');
        expect(params.size, equals(1));
        expect(params.has(''), isFalse);
        expect(params.get('foo'), equals('bar'));
      });
    });

    group('Performance characteristics', () {
      test('get operation is fast for large datasets', () {
        final params = URLSearchParams();

        // Add 1000 parameters
        for (int i = 0; i < 1000; i++) {
          params.append('param$i', 'value$i');
        }

        // Getting any parameter should be fast (O(1) lookup)
        final stopwatch = Stopwatch()..start();
        for (int i = 0; i < 100; i++) {
          params.get('param500');
        }
        stopwatch.stop();

        // Should complete in reasonable time (this is a smoke test)
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('has operation is fast for large datasets', () {
        final params = URLSearchParams();

        // Add 1000 parameters
        for (int i = 0; i < 1000; i++) {
          params.append('param$i', 'value$i');
        }

        // Checking existence should be fast (O(1) lookup)
        final stopwatch = Stopwatch()..start();
        for (int i = 0; i < 100; i++) {
          params.has('param500');
        }
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('stringify caching works correctly', () {
        final params = URLSearchParams.parse('foo=bar&baz=qux');

        // First call should compute the string
        final result1 = params.stringify();

        // Subsequent calls should use cached result
        final result2 = params.stringify();
        expect(result2, equals(result1));

        // Modifying should invalidate cache
        params.append('new', 'value');
        final result3 = params.stringify();
        expect(result3, isNot(equals(result1)));
        expect(result3, contains('new=value'));
      });
    });

    group('Web Standards compliance', () {
      test('maintains insertion order', () {
        final params = URLSearchParams();
        params.append('z', '1');
        params.append('a', '2');
        params.append('m', '3');

        final entries = params.entries().toList();
        expect(
          entries,
          equals([
            ['z', '1'],
            ['a', '2'],
            ['m', '3'],
          ]),
        );
      });

      test('allows duplicate parameter names', () {
        final params = URLSearchParams();
        params.append('foo', 'bar');
        params.append('foo', 'baz');

        expect(params.size, equals(2));
        expect(params.getAll('foo'), equals(['bar', 'baz']));
      });

      test('set() preserves position of first occurrence', () {
        final params = URLSearchParams.parse('a=1&b=2&a=3&c=4');
        params.set('a', 'new');

        final entries = params.entries().toList();
        expect(
          entries,
          equals([
            ['b', '2'],
            ['c', '4'],
            ['a', 'new'],
          ]),
        );
      });

      test('delete with value only removes matching entries', () {
        final params = URLSearchParams.parse('a=1&a=2&a=1&b=3');
        params.delete('a', '1');

        final entries = params.entries().toList();
        expect(
          entries,
          equals([
            ['a', '2'],
            ['b', '3'],
          ]),
        );
      });
    });
  });
}
