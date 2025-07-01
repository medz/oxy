import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:oxy/src/request.dart';
import 'package:oxy/src/headers.dart';
import 'package:oxy/src/body.dart';
import 'package:oxy/src/formdata.dart';
import 'package:oxy/src/abort.dart';

void main() {
  group('Request', () {
    group('constructor', () {
      test('creates request with minimal parameters', () {
        final request = Request('https://example.com');

        expect(request.url, equals('https://example.com'));
        expect(request.method, equals('GET'));
        expect(request.bodyUsed, isFalse);
        expect(request.headers, isNotNull);
        expect(request.signal, isNotNull);
        expect(request.cache, equals(RequestCache.defaults));
        expect(request.integrity, equals(''));
        expect(request.keepalive, isFalse);
        expect(request.mode, equals(RequestMode.cors));
        expect(request.priority, equals(RequestPriority.auto));
        expect(request.redirect, equals(RequestRedirect.follow));
        expect(request.referrer, equals('about:client'));
        expect(request.referrerPolicy, equals(ReferrerPolicy.empty));
        expect(request.credentials, equals(RequestCredentials.sameOrigin));
      });

      test('creates request with custom parameters', () {
        final customHeaders = Headers({'Authorization': 'Bearer token'});
        final customBody = Body.text('test data');
        final controller = AbortController();

        final request = Request(
          'https://api.example.com/data',
          method: 'POST',
          headers: customHeaders,
          body: customBody,
          signal: controller.signal,
          cache: RequestCache.noCache,
          integrity: 'sha256-hash',
          keepalive: true,
          mode: RequestMode.sameOrigin,
          priority: RequestPriority.high,
          redirect: RequestRedirect.error,
          referrer: 'https://example.com',
          referrerPolicy: ReferrerPolicy.noReferrer,
          credentials: RequestCredentials.include,
        );

        expect(request.url, equals('https://api.example.com/data'));
        expect(request.method, equals('POST'));
        expect(request.headers, equals(customHeaders));
        expect(request.signal, equals(controller.signal));
        expect(request.cache, equals(RequestCache.noCache));
        expect(request.integrity, equals('sha256-hash'));
        expect(request.keepalive, isTrue);
        expect(request.mode, equals(RequestMode.sameOrigin));
        expect(request.priority, equals(RequestPriority.high));
        expect(request.redirect, equals(RequestRedirect.error));
        expect(request.referrer, equals('https://example.com'));
        expect(request.referrerPolicy, equals(ReferrerPolicy.noReferrer));
        expect(request.credentials, equals(RequestCredentials.include));
      });

      test('normalizes method to uppercase', () {
        final request1 = Request('https://example.com', method: 'get');
        final request2 = Request('https://example.com', method: 'post');
        final request3 = Request('https://example.com', method: 'PUT');
        final request4 = Request('https://example.com', method: 'DeLeTe');

        expect(request1.method, equals('GET'));
        expect(request2.method, equals('POST'));
        expect(request3.method, equals('PUT'));
        expect(request4.method, equals('DELETE'));
      });

      test('creates default headers when none provided', () {
        final request = Request('https://example.com');
        expect(request.headers, isNotNull);
        // Default Body has Content-Type: application/octet-stream
        expect(request.headers.entries().length, equals(1));
        expect(
          request.headers.get('content-type'),
          equals('application/octet-stream'),
        );
      });

      test('creates default body when none provided', () {
        final request = Request('https://example.com');
        expect(request.bodyUsed, isFalse);
        expect(request.body, isNotNull);
      });

      test('creates default signal when none provided', () {
        final request = Request('https://example.com');
        expect(request.signal, isNotNull);
        expect(request.signal.aborted, isFalse);
      });
    });

    group('body header copying', () {
      test('copies body headers to request headers', () {
        final textBody = Body.text('Hello, World!');
        final request = Request(
          'https://api.example.com/notes',
          method: 'POST',
          body: textBody,
        );

        expect(request.url, equals('https://api.example.com/notes'));
        expect(request.method, equals('POST'));
        expect(
          request.headers.get('content-type'),
          equals('text/plain; charset=utf-8'),
        );
      });

      test('copies json body headers to request headers', () {
        final jsonBody = Body.json({'name': 'John', 'age': 30});
        final request = Request(
          'https://api.example.com/users',
          method: 'POST',
          body: jsonBody,
        );

        expect(request.headers.get('content-type'), equals('application/json'));
      });

      test('copies bytes body headers to request headers', () {
        final bytesBody = Body.bytes(Uint8List.fromList([1, 2, 3, 4, 5]));
        final request = Request(
          'https://api.example.com/upload',
          method: 'POST',
          body: bytesBody,
        );

        expect(
          request.headers.get('content-type'),
          equals('application/octet-stream'),
        );
      });

      test('copies formdata body headers to request headers', () {
        final formData = FormData();
        formData.append('name', FormDataEntry.text('John'));
        final formBody = Body.formData(formData);

        final request = Request(
          'https://api.example.com/submit',
          method: 'POST',
          body: formBody,
        );

        final contentType = request.headers.get('content-type');
        expect(contentType, startsWith('multipart/form-data; boundary='));
      });

      test('does not override existing request headers', () {
        final customHeaders = Headers({'Content-Type': 'custom/type'});
        final textBody = Body.text('Hello, World!');

        final request = Request(
          'https://api.example.com/notes',
          method: 'POST',
          headers: customHeaders,
          body: textBody,
        );

        // Body headers are copied after custom headers, so they override
        expect(
          request.headers.get('content-type'),
          equals('text/plain; charset=utf-8'),
        );
      });

      test('adds additional headers from body', () {
        final customHeaders = Headers({'Authorization': 'Bearer token'});
        final jsonBody = Body.json({'data': 'test'});

        final request = Request(
          'https://api.example.com/data',
          method: 'POST',
          headers: customHeaders,
          body: jsonBody,
        );

        expect(request.headers.get('authorization'), equals('Bearer token'));
        expect(request.headers.get('content-type'), equals('application/json'));
      });
    });

    group('bodyUsed property', () {
      test('returns false initially', () {
        final body = Body.text('test');
        final request = Request('https://example.com', body: body);
        expect(request.bodyUsed, isFalse);
      });

      test('returns true after accessing body stream', () {
        final body = Body.text('test');
        final request = Request('https://example.com', body: body);
        expect(request.bodyUsed, isFalse);

        // Access the stream (this marks it as used)
        request.body.listen((_) {});
        expect(request.bodyUsed, isTrue);
      });

      test('returns true after consuming with bytes()', () async {
        final body = Body.text('test');
        final request = Request('https://example.com', body: body);
        expect(request.bodyUsed, isFalse);

        await request.bytes();
        expect(request.bodyUsed, isTrue);
      });

      test('returns true after consuming with text()', () async {
        final body = Body.text('test');
        final request = Request('https://example.com', body: body);
        expect(request.bodyUsed, isFalse);

        await request.text();
        expect(request.bodyUsed, isTrue);
      });

      test('returns true after consuming with json()', () async {
        final body = Body.json({'key': 'value'});
        final request = Request('https://example.com', body: body);
        expect(request.bodyUsed, isFalse);

        await request.json();
        expect(request.bodyUsed, isTrue);
      });
    });

    group('clone()', () {
      test('creates independent copy', () {
        final body = Body.text('test data');
        final original = Request('https://example.com', body: body);
        final cloned = original.clone();

        expect(original.bodyUsed, isFalse);
        expect(cloned.bodyUsed, isFalse);
        expect(identical(original, cloned), isFalse);
      });

      test('clones all properties correctly', () {
        final controller = AbortController();
        final headers = Headers({'Authorization': 'Bearer token'});

        final original = Request(
          'https://api.example.com/data',
          method: 'POST',
          headers: headers,
          body: Body.text('test'),
          signal: controller.signal,
          cache: RequestCache.noCache,
          integrity: 'hash',
          keepalive: true,
          mode: RequestMode.sameOrigin,
          priority: RequestPriority.high,
          redirect: RequestRedirect.error,
          referrer: 'https://referrer.com',
          referrerPolicy: ReferrerPolicy.origin,
          credentials: RequestCredentials.include,
        );

        final cloned = original.clone();

        expect(cloned.url, equals(original.url));
        expect(cloned.method, equals(original.method));
        expect(cloned.headers, equals(original.headers));
        expect(cloned.signal, equals(original.signal));
        expect(cloned.cache, equals(original.cache));
        expect(cloned.integrity, equals(original.integrity));
        expect(cloned.keepalive, equals(original.keepalive));
        expect(cloned.mode, equals(original.mode));
        expect(cloned.priority, equals(original.priority));
        expect(cloned.redirect, equals(original.redirect));
        expect(cloned.referrer, equals(original.referrer));
        expect(cloned.referrerPolicy, equals(original.referrerPolicy));
        expect(cloned.credentials, equals(original.credentials));
      });

      test('allows independent consumption', () async {
        final body = Body.text('test data');
        final original = Request('https://example.com', body: body);
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
        final original = Request('https://example.com', body: body);
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
        final request = Request('https://example.com', body: body);
        final result = await request.text();
        expect(result, equals('Hello, World! 🌍'));
      });

      test('bytes() returns correct byte content', () async {
        final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final body = Body.bytes(originalData);
        final request = Request('https://example.com', body: body);
        final result = await request.bytes();
        expect(result, equals(originalData));
      });

      test('json() returns correct parsed data', () async {
        final originalData = {'name': 'John', 'age': 30, 'active': true};
        final body = Body.json(originalData);
        final request = Request('https://example.com', body: body);
        final result = await request.json();
        expect(result, equals(originalData));
      });

      test('json() handles null data', () async {
        final body = Body.json(null);
        final request = Request('https://example.com', body: body);
        final result = await request.json();
        expect(result, isNull);
      });

      test('json() handles primitive data', () async {
        final body = Body.json(42);
        final request = Request('https://example.com', body: body);
        final result = await request.json();
        expect(result, equals(42));
      });

      test('json() handles list data', () async {
        final originalData = [1, 2, 3, 'test'];
        final body = Body.json(originalData);
        final request = Request('https://example.com', body: body);
        final result = await request.json();
        expect(result, equals(originalData));
      });

      test('formData() returns correct FormData', () async {
        final formData = FormData();
        formData.append('name', FormDataEntry.text('John'));
        formData.append('email', FormDataEntry.text('john@example.com'));
        final body = Body.formData(formData);
        final request = Request('https://example.com', body: body);

        final parsedFormData = await request.formData();
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
          final request = Request('https://example.com', body: textBody);

          expect(() => request.formData(), throwsA(isA<FormatException>()));
        },
      );

      test('formData() marks body as used', () async {
        final formData = FormData();
        formData.append('name', FormDataEntry.text('John'));
        final body = Body.formData(formData);
        final request = Request('https://example.com', body: body);

        expect(request.bodyUsed, isFalse);
        await request.formData();
        expect(request.bodyUsed, isTrue);
      });
    });

    group('error handling', () {
      test('throws when consuming already used body', () async {
        final body = Body.text('test');
        final request = Request('https://example.com', body: body);

        // First consumption should work
        await request.text();
        expect(request.bodyUsed, isTrue);

        // Second consumption should throw
        expect(() => request.text(), throwsStateError);
        expect(() => request.bytes(), throwsStateError);
        expect(() => request.json(), throwsStateError);
      });

      test('handles invalid JSON gracefully', () async {
        final invalidJson = 'invalid json {';
        final body = Body.text(invalidJson);
        final request = Request('https://example.com', body: body);

        expect(() => request.json(), throwsA(isA<FormatException>()));
      });
    });

    group('headers behavior', () {
      test('headers are case insensitive', () {
        final headers = Headers({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer token',
        });

        final request = Request('https://example.com', headers: headers);

        // Body headers override request headers, so it will be octet-stream from default Body
        expect(
          request.headers.get('content-type'),
          equals('application/octet-stream'),
        );
        expect(
          request.headers.get('CONTENT-TYPE'),
          equals('application/octet-stream'),
        );
        expect(request.headers.get('authorization'), equals('Bearer token'));
        expect(request.headers.get('AUTHORIZATION'), equals('Bearer token'));
      });

      test('body types set correct headers through copying', () {
        final textBody = Body.text('text');
        final textRequest = Request('https://example.com', body: textBody);

        final jsonBody = Body.json({});
        final jsonRequest = Request('https://example.com', body: jsonBody);

        final bytesBody = Body.bytes(Uint8List.fromList([1, 2, 3]));
        final bytesRequest = Request('https://example.com', body: bytesBody);

        final formData = FormData();
        final formBody = Body.formData(formData);
        final formRequest = Request('https://example.com', body: formBody);

        expect(
          textRequest.headers.get('content-type'),
          equals('text/plain; charset=utf-8'),
        );
        expect(
          jsonRequest.headers.get('content-type'),
          equals('application/json'),
        );
        expect(
          bytesRequest.headers.get('content-type'),
          equals('application/octet-stream'),
        );
        expect(
          formRequest.headers.get('content-type'),
          startsWith('multipart/form-data; boundary='),
        );
      });
    });

    group('integration tests', () {
      test('complete request lifecycle works correctly', () async {
        final originalData = {
          'user': 'john_doe',
          'action': 'create_post',
          'content': 'Hello, World!',
        };

        final jsonBody = Body.json(originalData);
        final request = Request(
          'https://api.example.com/posts',
          method: 'POST',
          headers: Headers({
            'Authorization': 'Bearer secret-token',
            'X-Client-Version': '1.0.0',
          }),
          body: jsonBody,
        );

        // Verify request properties
        expect(request.url, equals('https://api.example.com/posts'));
        expect(request.method, equals('POST'));
        expect(
          request.headers.get('authorization'),
          equals('Bearer secret-token'),
        );
        expect(request.headers.get('x-client-version'), equals('1.0.0'));
        expect(request.headers.get('content-type'), equals('application/json'));

        // Clone and verify both work
        final clonedRequest = request.clone();

        final data1 = await request.json();
        final data2 = await clonedRequest.json();

        expect(data1, equals(originalData));
        expect(data2, equals(originalData));
        expect(request.bodyUsed, isTrue);
        expect(clonedRequest.bodyUsed, isTrue);
      });
    });
  });
}
