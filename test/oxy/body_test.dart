import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';

void main() {
  group('Body', () {
    group('constructor', () {
      test('creates body with empty stream', () {
        final body = Body(Stream.empty());
        expect(body.bodyUsed, isFalse);
        expect(body.headers, isNotNull);
        expect(
          body.headers.get('content-type'),
          equals('application/octet-stream'),
        );
      });

      test('creates body with data stream', () {
        final data = Uint8List.fromList([1, 2, 3]);
        final body = Body(Stream.value(data));
        expect(body.bodyUsed, isFalse);
        expect(body.headers, isNotNull);
        expect(
          body.headers.get('content-type'),
          equals('application/octet-stream'),
        );
      });
    });

    group('factory constructors', () {
      group('Body.text()', () {
        test('creates body with correct content-type for all text types', () {
          final regularBody = Body.text('Hello, World!');
          final emptyBody = Body.text('');
          final unicodeBody = Body.text('Hello 🌍');

          for (final body in [regularBody, emptyBody, unicodeBody]) {
            expect(
              body.headers.get('content-type'),
              equals('text/plain; charset=utf-8'),
            );
            expect(body.bodyUsed, isFalse);
          }
        });
      });

      group('Body.json()', () {
        test('creates body with correct content-type for any data type', () {
          final objectBody = Body.json({'key': 'value'});
          final nullBody = Body.json(null);
          final listBody = Body.json([1, 2, 3]);
          final primitiveBody = Body.json(42);

          for (final body in [objectBody, nullBody, listBody, primitiveBody]) {
            expect(
              body.headers.get('content-type'),
              equals('application/json'),
            );
            expect(body.bodyUsed, isFalse);
          }
        });
      });

      group('Body.bytes()', () {
        test('creates body with correct content-type header', () {
          final data = Uint8List.fromList([1, 2, 3]);
          final body = Body.bytes(data);
          expect(
            body.headers.get('content-type'),
            equals('application/octet-stream'),
          );
          expect(body.bodyUsed, isFalse);
        });

        test('creates body with empty bytes', () {
          final data = Uint8List.fromList([]);
          final body = Body.bytes(data);
          expect(
            body.headers.get('content-type'),
            equals('application/octet-stream'),
          );
          expect(body.bodyUsed, isFalse);
        });
      });

      group('Body.formData()', () {
        test('creates body with correct content-type header', () {
          final formData = FormData();
          formData.append('name', FormDataEntry.text('value'));
          final body = Body.formData(formData);

          final contentType = body.headers.get('content-type');
          expect(contentType, startsWith('multipart/form-data; boundary='));
          expect(body.bodyUsed, isFalse);
        });

        test('creates body with empty formData', () {
          final formData = FormData();
          final body = Body.formData(formData);

          final contentType = body.headers.get('content-type');
          expect(contentType, startsWith('multipart/form-data; boundary='));
          expect(body.bodyUsed, isFalse);
        });
      });
    });

    group('bodyUsed property', () {
      test('returns false initially', () {
        final body = Body.text('test');
        expect(body.bodyUsed, isFalse);
      });

      test('returns true after accessing body stream', () {
        final body = Body.text('test');
        expect(body.bodyUsed, isFalse);

        // Access the stream (this marks it as used)
        body.body.listen((_) {});
        expect(body.bodyUsed, isTrue);
      });

      test('returns true after consuming with bytes()', () async {
        final body = Body.text('test');
        expect(body.bodyUsed, isFalse);

        await body.bytes();
        expect(body.bodyUsed, isTrue);
      });

      test('returns true after consuming with text()', () async {
        final body = Body.text('test');
        expect(body.bodyUsed, isFalse);

        await body.text();
        expect(body.bodyUsed, isTrue);
      });

      test('returns true after consuming with json()', () async {
        final body = Body.json({'key': 'value'});
        expect(body.bodyUsed, isFalse);

        await body.json();
        expect(body.bodyUsed, isTrue);
      });
    });

    group('clone()', () {
      test('creates independent copy', () {
        final original = Body.text('test data');
        final cloned = original.clone();

        expect(original.bodyUsed, isFalse);
        expect(cloned.bodyUsed, isFalse);
        expect(identical(original, cloned), isFalse);
      });

      test('clones headers independently', () {
        final original = Body.text('test');
        final cloned = original.clone();

        // Headers should have same content but be different instances
        expect(
          original.headers.get('content-type'),
          equals(cloned.headers.get('content-type')),
        );
        expect(identical(original.headers, cloned.headers), isFalse);
      });

      test('allows independent consumption', () async {
        final original = Body.text('test data');
        final cloned = original.clone();

        // Consume original
        final originalResult = await original.text();
        expect(original.bodyUsed, isTrue);
        expect(cloned.bodyUsed, isFalse);

        // Consume clone
        final clonedResult = await cloned.text();
        expect(cloned.bodyUsed, isTrue);

        // Both should have same content
        expect(originalResult, equals(clonedResult));
        expect(originalResult, equals('test data'));
      });

      test('can be chained multiple times', () {
        final original = Body.text('test');
        final clone1 = original.clone();
        final clone2 = clone1.clone();
        final clone3 = original.clone();

        expect(original.bodyUsed, isFalse);
        expect(clone1.bodyUsed, isFalse);
        expect(clone2.bodyUsed, isFalse);
        expect(clone3.bodyUsed, isFalse);
      });
    });

    group('headers property', () {
      test('is accessible without marking body as used', () {
        final body = Body.text('test');
        final headers = body.headers;

        expect(headers, isNotNull);
        expect(body.bodyUsed, isFalse);
      });

      test('contains correct headers for different factory methods', () {
        final textBody = Body.text('test');
        final jsonBody = Body.json({});
        final bytesBody = Body.bytes(Uint8List(0));

        expect(textBody.headers.get('content-type'), contains('text/plain'));
        expect(
          jsonBody.headers.get('content-type'),
          contains('application/json'),
        );
        expect(
          bytesBody.headers.get('content-type'),
          contains('application/octet-stream'),
        );
      });
    });

    group('content consumption', () {
      test('text() returns correct string content', () async {
        final body = Body.text('Hello, World! 🌍');
        final result = await body.text();
        expect(result, equals('Hello, World! 🌍'));
      });

      test('bytes() returns correct byte content', () async {
        final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final body = Body.bytes(originalData);
        final result = await body.bytes();
        expect(result, equals(originalData));
      });

      test('json() returns correct parsed data', () async {
        final originalData = {'name': 'John', 'age': 30, 'active': true};
        final body = Body.json(originalData);
        final result = await body.json();
        expect(result, equals(originalData));
      });

      test('json() handles null data', () async {
        final body = Body.json(null);
        final result = await body.json();
        expect(result, isNull);
      });

      test('json() handles primitive data', () async {
        final body = Body.json(42);
        final result = await body.json();
        expect(result, equals(42));
      });

      test('json() handles list data', () async {
        final originalData = [1, 2, 3, 'test'];
        final body = Body.json(originalData);
        final result = await body.json();
        expect(result, equals(originalData));
      });
    });

    group('error handling', () {
      test('throws when consuming already used body', () async {
        final body = Body.text('test');

        // First consumption should work
        await body.text();
        expect(body.bodyUsed, isTrue);

        // Second consumption should throw
        expect(() => body.text(), throwsStateError);
        expect(() => body.bytes(), throwsStateError);
        expect(() => body.json(), throwsStateError);
      });

      test('handles invalid JSON gracefully', () async {
        final invalidJson = 'invalid json {';
        final body = Body.text(invalidJson);

        expect(() => body.json(), throwsA(isA<FormatException>()));
      });
    });

    group('formData() method', () {
      test('parses valid multipart/form-data', () async {
        final formData = FormData();
        formData.append('name', FormDataEntry.text('John'));
        formData.append('email', FormDataEntry.text('john@example.com'));
        final body = Body.formData(formData);

        final parsedFormData = await body.formData();
        expect(parsedFormData, isA<FormData>());

        final nameEntry = parsedFormData.get('name') as FormDataTextEntry;
        expect(nameEntry.text, equals('John'));

        final emailEntry = parsedFormData.get('email') as FormDataTextEntry;
        expect(emailEntry.text, equals('john@example.com'));
      });

      test('throws FormatException for non-multipart content', () async {
        final textBody = Body.text('test');
        expect(() => textBody.formData(), throwsA(isA<FormatException>()));

        final jsonBody = Body.json({'key': 'value'});
        expect(() => jsonBody.formData(), throwsA(isA<FormatException>()));

        final bytesBody = Body.bytes(Uint8List.fromList([1, 2, 3]));
        expect(() => bytesBody.formData(), throwsA(isA<FormatException>()));
      });

      test('throws FormatException when boundary is missing', () async {
        final body = Body(Stream.value(Uint8List.fromList([1, 2, 3])));
        // Override the headers to simulate multipart without boundary
        body.headers.set('Content-Type', 'multipart/form-data');
        expect(() => body.formData(), throwsA(isA<FormatException>()));
      });

      test('handles empty FormData', () async {
        final formData = FormData();
        final body = Body.formData(formData);

        final parsedFormData = await body.formData();
        expect(parsedFormData, isA<FormData>());
        expect(parsedFormData.entries().length, equals(0));
      });

      test('preserves file entries', () async {
        final formData = FormData();
        formData.append('name', FormDataEntry.text('John'));
        formData.append(
          'file',
          FormDataEntry.file(
            Stream.value(Uint8List.fromList([1, 2, 3, 4, 5])),
            filename: 'test.txt',
            contentType: 'text/plain',
          ),
        );
        final body = Body.formData(formData);

        final parsedFormData = await body.formData();

        final nameEntry = parsedFormData.get('name') as FormDataTextEntry;
        expect(nameEntry.text, equals('John'));

        final fileEntry = parsedFormData.get('file');
        expect(fileEntry, isA<FormDataFileEntry>());
        // Note: Testing the actual properties would require checking the FormDataFileEntry
        // For now, just verify we got an entry back
      });

      test('marks body as used after parsing', () async {
        final formData = FormData();
        formData.append('name', FormDataEntry.text('John'));
        final body = Body.formData(formData);

        expect(body.bodyUsed, isFalse);
        await body.formData();
        expect(body.bodyUsed, isTrue);
      });
    });
  });
}
