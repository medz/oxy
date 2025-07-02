import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';

void main() {
  group('Response', () {
    group('constructor', () {
      test('creates response with default parameters', () {
        final response = Response();

        expect(response.status, equals(200));
        expect(response.statusText, equals('OK'));
        expect(response.headers, isNotNull);
        expect(response.headers.entries().length, equals(0));
        expect(response.url, equals(''));
        expect(response.redirected, isFalse);
        expect(response.type, equals(ResponseType.basic));
        expect(response.bodyUsed, isFalse);
        expect(response.ok, isTrue);
      });

      test('creates response with custom parameters', () {
        final customHeaders = Headers({'Content-Type': 'application/json'});
        final customBody = Body.text('response data');

        final response = Response(
          status: 404,
          statusText: 'Custom Not Found',
          headers: customHeaders,
          body: customBody,
          url: 'https://api.example.com/missing',
          redirected: true,
          type: ResponseType.cors,
        );

        expect(response.status, equals(404));
        expect(response.statusText, equals('Custom Not Found'));
        expect(response.headers, equals(customHeaders));
        expect(response.url, equals('https://api.example.com/missing'));
        expect(response.redirected, isTrue);
        expect(response.type, equals(ResponseType.cors));
        expect(response.ok, isFalse);
      });

      test('automatically looks up statusText from statusMap', () {
        final response200 = Response(status: 200);
        final response404 = Response(status: 404);
        final response500 = Response(status: 500);
        final responseUnknown = Response(status: 999);

        expect(response200.statusText, equals('OK'));
        expect(response404.statusText, equals('Not Found'));
        expect(response500.statusText, equals('Internal Server Error'));
        expect(responseUnknown.statusText, equals('Unknown'));
      });

      test('custom statusText overrides statusMap lookup', () {
        final response = Response(status: 200, statusText: 'Custom Success');

        expect(response.status, equals(200));
        expect(response.statusText, equals('Custom Success'));
      });

      test('creates empty headers and body when none provided', () {
        final response = Response();
        expect(response.headers, isNotNull);
        expect(response.headers.entries().length, equals(0));
        expect(response.bodyUsed, isFalse);
        expect(response.body, isNotNull);
      });
    });

    group('ok property', () {
      test('returns true for 2xx status codes', () {
        expect(Response(status: 200).ok, isTrue);
        expect(Response(status: 201).ok, isTrue);
        expect(Response(status: 299).ok, isTrue);
      });

      test('returns false for non-2xx status codes', () {
        expect(Response(status: 0).ok, isFalse);
        expect(Response(status: 100).ok, isFalse);
        expect(Response(status: 199).ok, isFalse);
        expect(Response(status: 300).ok, isFalse);
        expect(Response(status: 404).ok, isFalse);
        expect(Response(status: 500).ok, isFalse);
      });
    });

    group('factory constructors', () {
      group('Response.error()', () {
        test('creates error response with correct properties', () {
          final response = Response.error();

          expect(response.status, equals(0));
          expect(response.statusText, equals('Unknown'));
          expect(response.type, equals(ResponseType.error));
          expect(response.ok, isFalse);
          expect(response.url, equals(''));
          expect(response.redirected, isFalse);
          expect(response.bodyUsed, isFalse);
        });
      });

      group('Response.redirect()', () {
        test('creates redirect response with default status 302', () {
          final response = Response.redirect('https://example.com/new');

          expect(response.status, equals(302));
          expect(response.statusText, equals('Found'));
          expect(
            response.headers.get('location'),
            equals('https://example.com/new'),
          );
          expect(response.type, equals(ResponseType.basic));
          expect(response.ok, isFalse);
        });

        test('creates redirect response with custom status', () {
          final response = Response.redirect(
            'https://example.com/moved',
            status: 301,
          );

          expect(response.status, equals(301));
          expect(response.statusText, equals('Moved Permanently'));
          expect(
            response.headers.get('location'),
            equals('https://example.com/moved'),
          );
        });

        test('sets location header correctly', () {
          final response = Response.redirect(
            'https://api.example.com/v2/users',
          );
          expect(
            response.headers.get('location'),
            equals('https://api.example.com/v2/users'),
          );
        });
      });

      group('Response.json()', () {
        test('creates response with json data and correct headers', () {
          final data = {'message': 'Hello', 'count': 42};
          final response = Response.json(data);

          expect(response.status, equals(200));
          expect(response.statusText, equals('OK'));
          expect(
            response.headers.get('content-type'),
            equals('application/json'),
          );
          expect(response.ok, isTrue);
        });

        test('handles null data', () {
          final response = Response.json(null);
          expect(
            response.headers.get('content-type'),
            equals('application/json'),
          );
        });

        test('handles primitive data', () {
          final response1 = Response.json(42);
          final response2 = Response.json('string');
          final response3 = Response.json(true);

          expect(
            response1.headers.get('content-type'),
            equals('application/json'),
          );
          expect(
            response2.headers.get('content-type'),
            equals('application/json'),
          );
          expect(
            response3.headers.get('content-type'),
            equals('application/json'),
          );
        });

        test('handles list data', () {
          final response = Response.json([1, 2, 3, 'test']);
          expect(
            response.headers.get('content-type'),
            equals('application/json'),
          );
        });

        test('allows custom status and statusText', () {
          final response = Response.json(
            {'error': 'Not found'},
            status: 404,
            statusText: 'Resource Missing',
          );

          expect(response.status, equals(404));
          expect(response.statusText, equals('Resource Missing'));
          expect(response.ok, isFalse);
        });

        test('merges headers correctly', () {
          final customHeaders = Headers({'X-Custom': 'value'});
          final response = Response.json({
            'data': 'test',
          }, headers: customHeaders);

          expect(response.headers.get('x-custom'), equals('value'));
          expect(
            response.headers.get('content-type'),
            equals('application/json'),
          );
        });

        test('response headers take precedence over body headers', () {
          final customHeaders = Headers({'Content-Type': 'custom/type'});
          final response = Response.json({
            'data': 'test',
          }, headers: customHeaders);

          expect(response.headers.get('content-type'), equals('custom/type'));
        });

        test('can consume json content', () async {
          final originalData = {'name': 'John', 'age': 30};
          final response = Response.json(originalData);

          final data = await response.json();
          expect(data, equals(originalData));
          expect(response.bodyUsed, isTrue);
        });
      });
    });

    group('bodyUsed property', () {
      test('returns false initially', () {
        final body = Body.text('test');
        final response = Response(body: body);
        expect(response.bodyUsed, isFalse);
      });

      test('returns true after accessing body stream', () {
        final body = Body.text('test');
        final response = Response(body: body);
        expect(response.bodyUsed, isFalse);

        // Access the stream (this marks it as used)
        response.body.listen((_) {});
        expect(response.bodyUsed, isTrue);
      });

      test('returns true after consuming with bytes()', () async {
        final body = Body.text('test');
        final response = Response(body: body);
        expect(response.bodyUsed, isFalse);

        await response.bytes();
        expect(response.bodyUsed, isTrue);
      });

      test('returns true after consuming with text()', () async {
        final body = Body.text('test');
        final response = Response(body: body);
        expect(response.bodyUsed, isFalse);

        await response.text();
        expect(response.bodyUsed, isTrue);
      });

      test('returns true after consuming with json()', () async {
        final response = Response.json({'key': 'value'});
        expect(response.bodyUsed, isFalse);

        await response.json();
        expect(response.bodyUsed, isTrue);
      });
    });

    group('clone()', () {
      test('creates independent copy', () {
        final body = Body.text('test data');
        final original = Response(body: body);
        final cloned = original.clone();

        expect(original.bodyUsed, isFalse);
        expect(cloned.bodyUsed, isFalse);
        expect(identical(original, cloned), isFalse);
      });

      test('clones all properties correctly', () {
        final headers = Headers({'X-Custom': 'value'});

        final original = Response(
          status: 404,
          statusText: 'Custom Not Found',
          headers: headers,
          body: Body.text('error message'),
          url: 'https://api.example.com/missing',
          redirected: true,
          type: ResponseType.cors,
        );

        final cloned = original.clone();

        expect(cloned.status, equals(original.status));
        expect(cloned.statusText, equals(original.statusText));
        expect(cloned.url, equals(original.url));
        expect(cloned.redirected, equals(original.redirected));
        expect(cloned.type, equals(original.type));
      });

      test('clones headers independently', () {
        final body = Body.text('test');
        final original = Response(body: body);
        final cloned = original.clone();

        // Headers should have same content but be different instances
        expect(identical(original.headers, cloned.headers), isFalse);
      });

      test('allows independent consumption', () async {
        final body = Body.text('test data');
        final original = Response(body: body);
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
        final body = Body.text('test');
        final original = Response(body: body);
        final clone1 = original.clone();
        final clone2 = clone1.clone();
        final clone3 = original.clone();

        expect(original.bodyUsed, isFalse);
        expect(clone1.bodyUsed, isFalse);
        expect(clone2.bodyUsed, isFalse);
        expect(clone3.bodyUsed, isFalse);
      });
    });

    group('content consumption', () {
      test('text() returns correct string content', () async {
        final body = Body.text('Hello, World! 🌍');
        final response = Response(body: body);
        final result = await response.text();
        expect(result, equals('Hello, World! 🌍'));
      });

      test('bytes() returns correct byte content', () async {
        final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final body = Body.bytes(originalData);
        final response = Response(body: body);
        final result = await response.bytes();
        expect(result, equals(originalData));
      });

      test('json() returns correct parsed data', () async {
        final originalData = {'name': 'John', 'age': 30, 'active': true};
        final response = Response.json(originalData);
        final result = await response.json();
        expect(result, equals(originalData));
      });

      test('json() handles null data', () async {
        final response = Response.json(null);
        final result = await response.json();
        expect(result, isNull);
      });

      test('json() handles primitive data', () async {
        final response = Response.json(42);
        final result = await response.json();
        expect(result, equals(42));
      });

      test('json() handles list data', () async {
        final originalData = [1, 2, 3, 'test'];
        final response = Response.json(originalData);
        final result = await response.json();
        expect(result, equals(originalData));
      });

      test('formData() returns correct FormData', () async {
        final formData = FormData();
        formData.append('name', FormDataEntry.text('John'));
        formData.append('email', FormDataEntry.text('john@example.com'));
        final body = Body.formData(formData);
        final response = Response(body: body);

        final parsedFormData = await response.formData();
        expect(parsedFormData, isA<FormData>());

        final nameEntry = parsedFormData.get('name') as FormDataTextEntry;
        expect(nameEntry.text, equals('John'));

        final emailEntry = parsedFormData.get('email') as FormDataTextEntry;
        expect(emailEntry.text, equals('john@example.com'));
      });

      test(
        'formData() throws FormatException for non-multipart content',
        () async {
          final textBody = Body.text('test data');
          final response = Response(body: textBody);

          expect(() => response.formData(), throwsA(isA<FormatException>()));
        },
      );

      test('formData() marks body as used', () async {
        final formData = FormData();
        formData.append('name', FormDataEntry.text('John'));
        final body = Body.formData(formData);
        final response = Response(body: body);

        expect(response.bodyUsed, isFalse);
        await response.formData();
        expect(response.bodyUsed, isTrue);
      });
    });

    group('error handling', () {
      test('throws when consuming already used body', () async {
        final body = Body.text('test');
        final response = Response(body: body);

        // First consumption should work
        await response.text();
        expect(response.bodyUsed, isTrue);

        // Second consumption should throw
        expect(() => response.text(), throwsStateError);
        expect(() => response.bytes(), throwsStateError);
        expect(() => response.json(), throwsStateError);
      });

      test('handles invalid JSON gracefully', () async {
        final invalidJson = 'invalid json {';
        final body = Body.text(invalidJson);
        final response = Response(body: body);

        expect(() => response.json(), throwsA(isA<FormatException>()));
      });
    });

    group('headers behavior', () {
      test('headers are case insensitive', () {
        final headers = Headers({
          'Content-Type': 'application/json',
          'X-Custom-Header': 'value',
        });

        final response = Response(headers: headers);

        expect(
          response.headers.get('content-type'),
          equals('application/json'),
        );
        expect(
          response.headers.get('CONTENT-TYPE'),
          equals('application/json'),
        );
        expect(response.headers.get('x-custom-header'), equals('value'));
        expect(response.headers.get('X-CUSTOM-HEADER'), equals('value'));
      });

      test('json factory method sets correct headers', () {
        final jsonResponse = Response.json({});

        expect(
          jsonResponse.headers.get('content-type'),
          equals('application/json'),
        );
      });
    });

    group('status text handling', () {
      test('uses statusMap for common status codes', () {
        expect(Response(status: 200).statusText, equals('OK'));
        expect(Response(status: 201).statusText, equals('Created'));
        expect(Response(status: 301).statusText, equals('Moved Permanently'));
        expect(Response(status: 404).statusText, equals('Not Found'));
        expect(
          Response(status: 500).statusText,
          equals('Internal Server Error'),
        );
      });

      test('uses Unknown for unrecognized status codes', () {
        expect(Response(status: 999).statusText, equals('Unknown'));
        expect(Response(status: 123).statusText, equals('Unknown'));
      });

      test('custom statusText overrides map lookup', () {
        final response = Response(status: 404, statusText: 'Page Missing');
        expect(response.statusText, equals('Page Missing'));
      });
    });

    group('integration tests', () {
      test('complete response lifecycle works correctly', () async {
        final originalData = {
          'users': [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
          ],
          'total': 2,
        };

        final response = Response.json(
          originalData,
          status: 200,
          headers: Headers({
            'X-Total-Count': '2',
            'Cache-Control': 'max-age=3600',
          }),
        );

        // Verify response properties
        expect(response.status, equals(200));
        expect(response.statusText, equals('OK'));
        expect(response.ok, isTrue);
        expect(response.headers.get('x-total-count'), equals('2'));
        expect(response.headers.get('cache-control'), equals('max-age=3600'));
        expect(
          response.headers.get('content-type'),
          equals('application/json'),
        );

        // Clone and verify both work
        final clonedResponse = response.clone();

        final data1 = await response.json();
        final data2 = await clonedResponse.json();

        expect(data1, equals(originalData));
        expect(data2, equals(originalData));
        expect(response.bodyUsed, isTrue);
        expect(clonedResponse.bodyUsed, isTrue);
      });

      test('error response behavior', () {
        final errorResponse = Response.error();

        expect(errorResponse.status, equals(0));
        expect(errorResponse.ok, isFalse);
        expect(errorResponse.type, equals(ResponseType.error));
        expect(errorResponse.statusText, equals('Unknown'));
      });

      test('redirect response behavior', () {
        final redirectResponse = Response.redirect(
          'https://new-location.com/page',
          status: 301,
        );

        expect(redirectResponse.status, equals(301));
        expect(redirectResponse.ok, isFalse);
        expect(redirectResponse.statusText, equals('Moved Permanently'));
        expect(
          redirectResponse.headers.get('location'),
          equals('https://new-location.com/page'),
        );
      });
    });
  });
}
