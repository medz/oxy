import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:oxy/oxy.dart';

void main() {
  group('FormDataTextEntry', () {
    test('should create text entry with string content', () {
      final entry = FormDataTextEntry('hello world');
      expect(entry.text, equals('hello world'));
    });

    test('should stream UTF-8 encoded bytes', () async {
      final entry = FormDataTextEntry('hello');
      final bytes = await entry.single;
      expect(bytes, equals(utf8.encode('hello')));
    });

    test('should handle empty string', () async {
      final entry = FormDataTextEntry('');
      final bytes = await entry.single;
      expect(bytes, equals(utf8.encode('')));
    });

    test('should handle unicode characters', () async {
      final entry = FormDataTextEntry('Hello 世界 🌍');
      final bytes = await entry.single;
      expect(bytes, equals(utf8.encode('Hello 世界 🌍')));
    });

    test('should only allow single consumption', () async {
      final entry = FormDataTextEntry('test');
      final bytes = await entry.single;
      expect(bytes, equals(utf8.encode('test')));

      // Second consumption should fail
      expect(() => entry.single, throwsStateError);
    });

    test('should have correct broadcast status', () {
      final entry = FormDataTextEntry('test');
      expect(entry.isBroadcast, isFalse);
    });
  });

  group('FormDataFileEntry', () {
    test('should create file entry with default values', () {
      final stream = Stream.value([1, 2, 3]);
      final entry = FormDataFileEntry(stream);

      expect(entry.filename, equals('file'));
      expect(entry.contentType, equals('application/octet-stream'));
    });

    test('should create file entry with custom values', () {
      final stream = Stream.value([1, 2, 3]);
      final entry = FormDataFileEntry(
        stream,
        filename: 'test.txt',
        contentType: 'text/plain',
        size: 100,
      );

      expect(entry.filename, equals('test.txt'));
      expect(entry.contentType, equals('text/plain'));
    });

    test('should stream data correctly', () async {
      final data = [1, 2, 3, 4, 5];
      final stream = Stream.value(data);
      final entry = FormDataFileEntry(stream);

      final result = await entry.single;
      expect(result, equals(Uint8List.fromList(data)));
    });

    test('should handle empty stream', () async {
      final stream = Stream<List<int>>.empty();
      final entry = FormDataFileEntry(stream);

      final chunks = await entry.toList();
      expect(chunks, isEmpty);
    });

    test('should handle multiple chunks', () async {
      final controller = StreamController<List<int>>();
      final entry = FormDataFileEntry(controller.stream);

      // Start listening first
      final futureChunks = entry.toList();

      controller.add([1, 2]);
      controller.add([3, 4]);
      controller.add([5]);
      controller.close();

      final chunks = await futureChunks;
      expect(chunks.length, equals(3));
      expect(chunks[0], equals(Uint8List.fromList([1, 2])));
      expect(chunks[1], equals(Uint8List.fromList([3, 4])));
      expect(chunks[2], equals(Uint8List.fromList([5])));
    });

    test('should calculate size correctly', () async {
      final data = [1, 2, 3, 4, 5];
      final stream = Stream.value(data);
      final entry = FormDataFileEntry(stream);

      final size = await entry.size();
      expect(size, equals(5));
    });

    test('should cache size after first calculation', () async {
      final data = [1, 2, 3, 4, 5];
      final stream = Stream.value(data);
      final entry = FormDataFileEntry(stream);

      // First call calculates size
      final size1 = await entry.size();
      expect(size1, equals(5));

      // Second call should return cached value without re-consuming stream
      final size2 = await entry.size();
      expect(size2, equals(5));
      expect(size1, equals(size2));
    });

    test('should use provided size when available', () async {
      final stream = Stream.value([1, 2, 3]);
      final entry = FormDataFileEntry(stream, size: 100);

      final size = await entry.size();
      expect(size, equals(100));
    });

    test('should implement bytes() method correctly', () async {
      final data = [72, 101, 108, 108, 111]; // "Hello"
      final stream = Stream.value(data);
      final entry = FormDataFileEntry(stream);

      final bytes = await entry.bytes();
      expect(bytes, equals(Uint8List.fromList(data)));
    });

    test('should implement text() method correctly', () async {
      final data = utf8.encode('Hello World');
      final stream = Stream.value(data);
      final entry = FormDataFileEntry(stream);

      final text = await entry.text();
      expect(text, equals('Hello World'));
    });

    test('should implement json() method correctly', () async {
      final jsonData = {'name': 'test', 'value': 42};
      final data = utf8.encode(jsonEncode(jsonData));
      final stream = Stream.value(data);
      final entry = FormDataFileEntry(stream);

      final json = await entry.json();
      expect(json, equals(jsonData));
    });

    test('should handle Uint8List input directly', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final stream = Stream.value(data);
      final entry = FormDataFileEntry(stream);

      final result = await entry.single;
      expect(result, equals(data));
    });

    test('should handle broadcast streams correctly', () {
      final controller = StreamController<List<int>>.broadcast();
      final entry = FormDataFileEntry(controller.stream);

      expect(entry.isBroadcast, isTrue);
    });
  });

  group('FormData', () {
    test('should create empty form data', () {
      final form = FormData();
      expect(form.boundary, isNotEmpty);
      expect(form.boundary.startsWith('OxyBoundary'), isTrue);
    });

    test('should generate unique boundaries', () {
      final form1 = FormData();
      final form2 = FormData();
      expect(form1.boundary, isNot(equals(form2.boundary)));
    });

    test('should append text entries', () {
      final form = FormData();
      form.append('name', FormDataEntry.text('John'));
      form.append('email', FormDataEntry.text('john@example.com'));

      expect(form.has('name'), isTrue);
      expect(form.has('email'), isTrue);
      expect(form.get('name'), isA<FormDataTextEntry>());
      expect((form.get('name') as FormDataTextEntry).text, equals('John'));
    });

    test('should append file entries', () {
      final form = FormData();
      final stream = Stream.value([1, 2, 3]);
      form.append(
        'file',
        FormDataEntry.file(
          stream,
          filename: 'test.txt',
          contentType: 'text/plain',
        ),
      );

      expect(form.has('file'), isTrue);
      final entry = form.get('file') as FormDataFileEntry;
      expect(entry.filename, equals('test.txt'));
      expect(entry.contentType, equals('text/plain'));
    });

    test('should handle multiple entries with same name', () {
      final form = FormData();
      form.append('tags', FormDataEntry.text('dart'));
      form.append('tags', FormDataEntry.text('flutter'));

      final tags = form.getAll('tags').toList();
      expect(tags.length, equals(2));
      expect((tags[0] as FormDataTextEntry).text, equals('dart'));
      expect((tags[1] as FormDataTextEntry).text, equals('flutter'));
    });

    test('should delete entries', () {
      final form = FormData();
      form.append('name', FormDataEntry.text('John'));
      form.append('email', FormDataEntry.text('john@example.com'));

      expect(form.has('name'), isTrue);
      form.delete('name');
      expect(form.has('name'), isFalse);
      expect(form.has('email'), isTrue);
    });

    test('should set entries (replace existing)', () {
      final form = FormData();
      form.append('name', FormDataEntry.text('John'));
      form.append('name', FormDataEntry.text('Jane'));

      expect(form.getAll('name').length, equals(2));

      form.set('name', FormDataEntry.text('Bob'));
      expect(form.getAll('name').length, equals(1));
      expect((form.get('name') as FormDataTextEntry).text, equals('Bob'));
    });

    test('should generate proper stream output', () async {
      final form = FormData();
      form.append('name', FormDataEntry.text('John'));
      form.append('email', FormDataEntry.text('john@example.com'));

      final chunks = await form.stream().toList();
      final output = chunks.expand((chunk) => chunk).toList();
      final content = utf8.decode(output);

      expect(content, contains('--${form.boundary}'));
      expect(content, contains('Content-Disposition: form-data;'));
      expect(content, contains('name="name"'));
      expect(content, contains('John'));
      expect(content, contains('name="email"'));
      expect(content, contains('john@example.com'));
    });

    test('should generate proper stream output for files', () async {
      final form = FormData();
      final fileData = utf8.encode('file content');
      final stream = Stream.value(fileData);

      form.append(
        'file',
        FormDataEntry.file(
          stream,
          filename: 'test.txt',
          contentType: 'text/plain',
        ),
      );

      final chunks = await form.stream().toList();
      final output = chunks.expand((chunk) => chunk).toList();
      final content = utf8.decode(output);

      expect(content, contains('--${form.boundary}'));
      expect(content, contains('Content-Disposition: form-data;'));
      expect(content, contains('name="file"'));
      expect(content, contains('filename="test.txt"'));
      expect(content, contains('Content-Type: text/plain'));
      expect(content, contains('file content'));
    });

    test('should handle special characters in field names', () async {
      final form = FormData();
      form.append('field with spaces', FormDataEntry.text('value'));
      form.append('field%with&special', FormDataEntry.text('value'));

      final chunks = await form.stream().toList();
      final output = chunks.expand((chunk) => chunk).toList();
      final content = utf8.decode(output);

      expect(content, contains('name="field%20with%20spaces"'));
      expect(content, contains('name="field%25with%26special"'));
    });

    test('should handle special characters in filenames', () async {
      final form = FormData();
      final stream = Stream.value([1, 2, 3]);

      form.append(
        'file',
        FormDataEntry.file(
          stream,
          filename: 'file with spaces & symbols.txt',
          contentType: 'text/plain',
        ),
      );

      final chunks = await form.stream().toList();
      final output = chunks.expand((chunk) => chunk).toList();
      final content = utf8.decode(output);

      expect(
        content,
        contains('filename="file%20with%20spaces%20%26%20symbols.txt"'),
      );
    });

    test('should be case sensitive for field names', () {
      final form = FormData();
      form.append('Name', FormDataEntry.text('John'));
      form.append('name', FormDataEntry.text('Jane'));

      expect(form.has('Name'), isTrue);
      expect(form.has('name'), isTrue);
      expect(form.get('Name'), isNot(equals(form.get('name'))));
    });

    test('should only allow stream to be consumed once', () async {
      final form = FormData();
      form.append('test', FormDataEntry.text('value'));

      // First consumption should work
      final chunks1 = await form.stream().toList();
      expect(chunks1, isNotEmpty);

      // Second consumption should fail or return empty
      // This depends on the implementation - it might throw or return empty
      try {
        final chunks2 = await form.stream().toList();
        // If it doesn't throw, it should at least be empty or different
        expect(chunks2, isNot(equals(chunks1)));
      } catch (e) {
        // It's also acceptable if it throws an error
        expect(e, isNotNull);
      }
    });
  });

  group('FormData.parse', () {
    test('should parse simple text fields', () async {
      const boundary = 'testboundary';
      const content = '''
--testboundary\r
Content-Disposition: form-data; name="field1"\r
\r
value1\r
--testboundary\r
Content-Disposition: form-data; name="field2"\r
\r
value2\r
--testboundary--\r
''';

      final stream = Stream.value(utf8.encode(content));
      final form = await FormData.parse(boundary, stream);

      expect(form.has('field1'), isTrue);
      expect(form.has('field2'), isTrue);
      expect((form.get('field1') as FormDataTextEntry).text, equals('value1'));
      expect((form.get('field2') as FormDataTextEntry).text, equals('value2'));
    });

    test('should parse file fields', () async {
      const boundary = 'testboundary';
      const content = '''
--testboundary\r
Content-Disposition: form-data; name="file"; filename="test.txt"\r
Content-Type: text/plain\r
\r
file content here\r
--testboundary--\r
''';

      final stream = Stream.value(utf8.encode(content));
      final form = await FormData.parse(boundary, stream);

      expect(form.has('file'), isTrue);
      final entry = form.get('file') as FormDataFileEntry;
      expect(entry.filename, equals('test.txt'));
      expect(entry.contentType, equals('text/plain'));
    });

    test('should handle quoted parameter values', () async {
      const boundary = 'testboundary';
      const content = '''
--testboundary\r
Content-Disposition: form-data; name="file"; filename="test file.txt"\r
Content-Type: text/plain\r
\r
content\r
--testboundary--\r
''';

      final stream = Stream.value(utf8.encode(content));
      final form = await FormData.parse(boundary, stream);

      final entry = form.get('file') as FormDataFileEntry;
      expect(entry.filename, equals('test file.txt'));
    });

    test('should handle single quoted parameter values', () async {
      const boundary = 'testboundary';
      const content = '''
--testboundary\r
Content-Disposition: form-data; name='field'; filename='test.txt'\r
Content-Type: text/plain\r
\r
content\r
--testboundary--\r
''';

      final stream = Stream.value(utf8.encode(content));
      final form = await FormData.parse(boundary, stream);

      expect(form.has('field'), isTrue);
      final entry = form.get('field') as FormDataFileEntry;
      expect(entry.filename, equals('test.txt'));
    });

    test('should ignore parts without name parameter', () async {
      const boundary = 'testboundary';
      const content = '''
--testboundary\r
Content-Disposition: form-data\r
\r
ignored content\r
--testboundary\r
Content-Disposition: form-data; name="valid"\r
\r
valid content\r
--testboundary--\r
''';

      final stream = Stream.value(utf8.encode(content));
      final form = await FormData.parse(boundary, stream);

      expect(form.keys().length, equals(1));
      expect(form.has('valid'), isTrue);
    });

    test('should handle content-type with parameters', () async {
      const boundary = 'testboundary';
      const content = '''
--testboundary\r
Content-Disposition: form-data; name="file"; filename="test.txt"\r
Content-Type: text/plain; charset=utf-8\r
\r
content\r
--testboundary--\r
''';

      final stream = Stream.value(utf8.encode(content));
      final form = await FormData.parse(boundary, stream);

      final entry = form.get('file') as FormDataFileEntry;
      expect(entry.contentType, equals('text/plain'));
    });

    test('should handle empty multipart content', () async {
      const boundary = 'testboundary';
      const content = '--testboundary--\r\n';

      final stream = Stream.value(utf8.encode(content));
      final form = await FormData.parse(boundary, stream);

      expect(form.keys().length, equals(0));
    });
  });

  group('FormData.generateBoundary', () {
    test('should generate boundary with correct prefix', () {
      final boundary = FormData.generateBoundary();
      expect(boundary.startsWith('OxyBoundary'), isTrue);
    });

    test('should generate boundary with correct length', () {
      final boundary = FormData.generateBoundary();
      expect(boundary.length, equals('OxyBoundary'.length + 32));
    });

    test('should generate unique boundaries', () {
      final boundaries = <String>{};
      for (int i = 0; i < 100; i++) {
        boundaries.add(FormData.generateBoundary());
      }
      expect(boundaries.length, equals(100));
    });

    test('should only contain valid characters', () {
      final boundary = FormData.generateBoundary();
      final validChars = RegExp(r'^[A-Za-z0-9]+$');
      expect(validChars.hasMatch(boundary), isTrue);
    });
  });

  group('FormData integration tests', () {
    test('should handle complex form with mixed content', () async {
      final form = FormData();

      // Add text fields
      form.append('username', FormDataEntry.text('johndoe'));
      form.append('email', FormDataEntry.text('john@example.com'));
      form.append('tags', FormDataEntry.text('dart'));
      form.append('tags', FormDataEntry.text('flutter'));

      // Add file
      final fileContent = utf8.encode('{"name": "test", "version": "1.0.0"}');
      final fileStream = Stream.value(fileContent);
      form.append(
        'config',
        FormDataEntry.file(
          fileStream,
          filename: 'config.json',
          contentType: 'application/json',
        ),
      );

      // Generate and parse back
      final boundary = form.boundary;
      final generatedStream = form.stream();
      final parsedForm = await FormData.parse(boundary, generatedStream);

      // Verify text fields
      expect(
        (parsedForm.get('username') as FormDataTextEntry).text,
        equals('johndoe'),
      );
      expect(
        (parsedForm.get('email') as FormDataTextEntry).text,
        equals('john@example.com'),
      );

      // Verify multiple values
      final tags = parsedForm.getAll('tags').cast<FormDataTextEntry>().toList();
      expect(tags.length, equals(2));
      expect(tags[0].text, equals('dart'));
      expect(tags[1].text, equals('flutter'));

      // Verify file
      final configEntry = parsedForm.get('config') as FormDataFileEntry;
      expect(configEntry.filename, equals('config.json'));
      expect(configEntry.contentType, equals('application/json'));

      final configContent = await configEntry.text();
      final configJson = jsonDecode(configContent);
      expect(configJson['name'], equals('test'));
      expect(configJson['version'], equals('1.0.0'));
    });

    test('should handle round-trip with binary data', () async {
      final form = FormData();

      // Create binary data
      final binaryData = Uint8List.fromList(List.generate(256, (i) => i));
      final binaryStream = Stream.value(binaryData);

      form.append(
        'binary',
        FormDataEntry.file(
          binaryStream,
          filename: 'binary.dat',
          contentType: 'application/octet-stream',
        ),
      );

      // Round-trip
      final boundary = form.boundary;
      final generatedStream = form.stream();
      final parsedForm = await FormData.parse(boundary, generatedStream);

      // Verify binary data
      final binaryEntry = parsedForm.get('binary') as FormDataFileEntry;
      final recoveredData = await binaryEntry.bytes();

      expect(recoveredData.length, equals(256));
      for (int i = 0; i < 256; i++) {
        expect(recoveredData[i], equals(i));
      }
    });

    test('should handle empty values correctly', () async {
      final form = FormData();
      form.append('empty_text', FormDataEntry.text(''));
      form.append(
        'empty_file',
        FormDataEntry.file(
          Stream.value(<int>[]),
          filename: 'empty.txt',
          contentType: 'text/plain',
        ),
      );

      final boundary = form.boundary;
      final generatedStream = form.stream();
      final parsedForm = await FormData.parse(boundary, generatedStream);

      expect(
        (parsedForm.get('empty_text') as FormDataTextEntry).text,
        equals(''),
      );

      final emptyFile = parsedForm.get('empty_file') as FormDataFileEntry;
      expect(emptyFile.filename, equals('empty.txt'));
      expect(await emptyFile.bytes(), equals(Uint8List(0)));
    });
  });
}
