import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('Response.decode', () {
    test('decodes JSON payload without custom decoder', () async {
      final response = Response.json({'ok': true});
      final decoded = await response.decode<Map<String, Object?>>();

      expect(decoded['ok'], isTrue);
    });

    test('maps decoded payload using custom decoder', () async {
      final response = Response.json({'name': 'oxy'});
      final decoded = await response.decode<String>(
        decoder: (value) => (value as Map<String, Object?>)['name'] as String,
      );

      expect(decoded, 'oxy');
    });

    test('throws OxyDecodeException when response body is not JSON', () async {
      final response = Response.text('not-json');

      expect(
        response.decode<Map<String, Object?>>(),
        throwsA(isA<OxyDecodeException>()),
      );
    });

    test('throws OxyDecodeException when target type cast fails', () async {
      final response = Response.json({'ok': true});

      expect(response.decode<int>(), throwsA(isA<OxyDecodeException>()));
    });
  });
}
