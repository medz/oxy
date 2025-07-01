import 'package:test/test.dart';
import 'package:oxy/src/headers.dart';

void main() {
  group('Headers', () {
    group('constructor', () {
      test('creates empty headers when no init provided', () {
        final headers = Headers();
        expect(headers.entries().length, equals(0));
      });

      test('creates headers from map', () {
        final headers = Headers({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer token123',
        });
        expect(headers.entries().length, equals(2));
      });

      test('creates headers from map with empty values', () {
        final headers = Headers({
          'Content-Type': '',
          'Authorization': 'Bearer token',
        });
        expect(headers.entries().length, equals(2));
      });
    });

    group('case insensitive behavior', () {
      test('get() is case insensitive', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');

        expect(headers.get('Content-Type'), equals('application/json'));
        expect(headers.get('content-type'), equals('application/json'));
        expect(headers.get('CONTENT-TYPE'), equals('application/json'));
        expect(headers.get('Content-type'), equals('application/json'));
      });

      test('has() is case insensitive', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');

        expect(headers.has('Content-Type'), isTrue);
        expect(headers.has('content-type'), isTrue);
        expect(headers.has('CONTENT-TYPE'), isTrue);
        expect(headers.has('Content-type'), isTrue);
      });

      test('set() overwrites regardless of case', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');
        headers.set('content-type', 'text/plain');

        expect(headers.get('Content-Type'), equals('text/plain'));
        expect(headers.get('content-type'), equals('text/plain'));
        expect(headers.entries().length, equals(1));
      });

      test('delete() removes regardless of case', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');

        expect(headers.has('Content-Type'), isTrue);
        headers.delete('content-type');
        expect(headers.has('Content-Type'), isFalse);
        expect(headers.has('content-type'), isFalse);
      });

      test('append() treats same names as case insensitive', () {
        final headers = Headers();
        headers.append('Accept', 'text/html');
        headers.append('accept', 'application/json');
        headers.append('ACCEPT', 'text/plain');

        final values = headers.getAll('Accept').toList();
        expect(values.length, equals(3));
        expect(
          values,
          containsAll(['text/html', 'application/json', 'text/plain']),
        );
      });
    });

    group('set() method', () {
      test('sets single value', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');

        expect(headers.get('Content-Type'), equals('application/json'));
        expect(headers.has('Content-Type'), isTrue);
      });

      test('overwrites existing value', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');
        headers.set('Content-Type', 'text/plain');

        expect(headers.get('Content-Type'), equals('text/plain'));
        expect(headers.entries().length, equals(1));
      });

      test('overwrites multiple values from append', () {
        final headers = Headers();
        headers.append('Accept', 'text/html');
        headers.append('Accept', 'application/json');
        headers.set('Accept', 'text/plain');

        expect(headers.get('Accept'), equals('text/plain'));
        expect(headers.getAll('Accept').length, equals(1));
      });
    });

    group('append() method', () {
      test('adds single value', () {
        final headers = Headers();
        headers.append('Accept', 'text/html');

        expect(headers.get('Accept'), equals('text/html'));
        expect(headers.getAll('Accept').length, equals(1));
      });

      test('adds multiple values for same header', () {
        final headers = Headers();
        headers.append('Accept', 'text/html');
        headers.append('Accept', 'application/json');
        headers.append('Accept', 'text/plain');

        expect(headers.get('Accept'), equals('text/html')); // First value
        final values = headers.getAll('Accept').toList();
        expect(values.length, equals(3));
        expect(values, equals(['text/html', 'application/json', 'text/plain']));
      });

      test('preserves order of addition', () {
        final headers = Headers();
        headers.append('Accept', 'first');
        headers.append('Content-Type', 'application/json');
        headers.append('Accept', 'second');
        headers.append('Authorization', 'Bearer token');
        headers.append('Accept', 'third');

        final acceptValues = headers.getAll('Accept').toList();
        expect(acceptValues, equals(['first', 'second', 'third']));
      });
    });

    group('get() method', () {
      test('returns null for non-existent header', () {
        final headers = Headers();
        expect(headers.get('Non-Existent'), isNull);
      });

      test('returns first value when multiple values exist', () {
        final headers = Headers();
        headers.append('Accept', 'first');
        headers.append('Accept', 'second');
        headers.append('Accept', 'third');

        expect(headers.get('Accept'), equals('first'));
      });

      test('returns null for set-cookie header', () {
        final headers = Headers();
        headers.append('Set-Cookie', 'sessionId=abc123');
        headers.append('Set-Cookie', 'theme=dark');

        expect(headers.get('Set-Cookie'), isNull);
        expect(headers.get('set-cookie'), isNull);
        expect(headers.get('SET-COOKIE'), isNull);
      });
    });

    group('getAll() method', () {
      test('returns empty iterable for non-existent header', () {
        final headers = Headers();
        expect(headers.getAll('Non-Existent'), isEmpty);
      });

      test('returns all values for header with multiple values', () {
        final headers = Headers();
        headers.append('Accept', 'text/html');
        headers.append('Accept', 'application/json');
        headers.append('Accept', 'text/plain');

        final values = headers.getAll('Accept').toList();
        expect(values.length, equals(3));
        expect(values, equals(['text/html', 'application/json', 'text/plain']));
      });

      test('returns single value as iterable', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');

        final values = headers.getAll('Content-Type').toList();
        expect(values.length, equals(1));
        expect(values.first, equals('application/json'));
      });

      test('returns empty iterable for set-cookie header', () {
        final headers = Headers();
        headers.append('Set-Cookie', 'sessionId=abc123');
        headers.append('Set-Cookie', 'theme=dark');

        expect(headers.getAll('Set-Cookie'), isEmpty);
        expect(headers.getAll('set-cookie'), isEmpty);
        expect(headers.getAll('SET-COOKIE'), isEmpty);
      });
    });

    group('has() method', () {
      test('returns false for non-existent header', () {
        final headers = Headers();
        expect(headers.has('Non-Existent'), isFalse);
      });

      test('returns true for existing header', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');

        expect(headers.has('Content-Type'), isTrue);
      });

      test('returns true for header with multiple values', () {
        final headers = Headers();
        headers.append('Accept', 'text/html');
        headers.append('Accept', 'application/json');

        expect(headers.has('Accept'), isTrue);
      });

      test('returns true for set-cookie header', () {
        final headers = Headers();
        headers.append('Set-Cookie', 'sessionId=abc123');

        expect(headers.has('Set-Cookie'), isTrue);
        expect(headers.has('set-cookie'), isTrue);
        expect(headers.has('SET-COOKIE'), isTrue);
      });
    });

    group('delete() method', () {
      test('removes single header', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');
        headers.set('Authorization', 'Bearer token');

        expect(headers.has('Content-Type'), isTrue);
        headers.delete('Content-Type');
        expect(headers.has('Content-Type'), isFalse);
        expect(headers.has('Authorization'), isTrue);
      });

      test('removes all values for header with multiple values', () {
        final headers = Headers();
        headers.append('Accept', 'text/html');
        headers.append('Accept', 'application/json');
        headers.append('Accept', 'text/plain');

        expect(headers.getAll('Accept').length, equals(3));
        headers.delete('Accept');
        expect(headers.getAll('Accept').length, equals(0));
        expect(headers.has('Accept'), isFalse);
      });

      test('has no effect on non-existent header', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');

        expect(headers.entries().length, equals(1));
        headers.delete('Non-Existent');
        expect(headers.entries().length, equals(1));
        expect(headers.has('Content-Type'), isTrue);
      });
    });

    group('getSetCookie() method', () {
      test('returns empty iterable when no set-cookie headers', () {
        final headers = Headers();
        expect(headers.getSetCookie(), isEmpty);
      });

      test('returns all set-cookie values', () {
        final headers = Headers();
        headers.append('Set-Cookie', 'sessionId=abc123; Path=/');
        headers.append('Set-Cookie', 'theme=dark; Path=/; Secure');
        headers.append('Set-Cookie', 'lang=en; Domain=.example.com');

        final cookies = headers.getSetCookie().toList();
        expect(cookies.length, equals(3));
        expect(
          cookies,
          containsAll([
            'sessionId=abc123; Path=/',
            'theme=dark; Path=/; Secure',
            'lang=en; Domain=.example.com',
          ]),
        );
      });

      test('works with different case variations', () {
        final headers = Headers();
        headers.append('Set-Cookie', 'first=value1');
        headers.append('set-cookie', 'second=value2');
        headers.append('SET-COOKIE', 'third=value3');

        final cookies = headers.getSetCookie().toList();
        expect(cookies.length, equals(3));
        expect(
          cookies,
          containsAll(['first=value1', 'second=value2', 'third=value3']),
        );
      });
    });

    group('entries() method', () {
      test('returns empty iterable for empty headers', () {
        final headers = Headers();
        expect(headers.entries(), isEmpty);
      });

      test('returns all entries', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');
        headers.set('Authorization', 'Bearer token');
        headers.append('Accept', 'text/html');
        headers.append('Accept', 'application/json');

        final entries = headers.entries().toList();
        expect(entries.length, equals(4));

        // Check that all entries are present
        final entryMap = <String, List<String>>{};
        for (final (name, value) in entries) {
          entryMap.putIfAbsent(name.toLowerCase(), () => []).add(value);
        }

        expect(entryMap['content-type'], equals(['application/json']));
        expect(entryMap['authorization'], equals(['Bearer token']));
        expect(entryMap['accept'], equals(['text/html', 'application/json']));
      });

      test('includes set-cookie headers in entries', () {
        final headers = Headers();
        headers.append('Set-Cookie', 'sessionId=abc123');
        headers.append('Set-Cookie', 'theme=dark');
        headers.set('Content-Type', 'text/html');

        final entries = headers.entries().toList();
        expect(entries.length, equals(3));

        final setCookieEntries = entries
            .where((entry) => entry.$1.toLowerCase() == 'set-cookie')
            .toList();
        expect(setCookieEntries.length, equals(2));
      });
    });

    group('integration tests', () {
      test('mixed operations work correctly', () {
        final headers = Headers({
          'Content-Type': 'text/html',
          'Accept': 'text/html',
        });

        // Add more accept values
        headers.append('Accept', 'application/json');
        headers.append('ACCEPT', 'text/plain');

        // Set authorization
        headers.set('Authorization', 'Bearer token123');

        // Update content-type
        headers.set('content-type', 'application/json');

        // Verify final state
        expect(headers.get('Content-Type'), equals('application/json'));
        expect(headers.get('Authorization'), equals('Bearer token123'));
        expect(headers.getAll('Accept').length, equals(3));
        expect(
          headers.getAll('accept').toList(),
          equals(['text/html', 'application/json', 'text/plain']),
        );
      });

      test('case preservation in entries', () {
        final headers = Headers();
        headers.set('Content-Type', 'application/json');
        headers.set('X-Custom-Header', 'custom-value');

        final entries = headers.entries().toList();

        // Original case should be preserved in entries
        final entryNames = entries.map((entry) => entry.$1).toList();
        expect(entryNames, contains('Content-Type'));
        expect(entryNames, contains('X-Custom-Header'));
      });
    });
  });
}
