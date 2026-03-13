import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('LoggingMiddleware', () {
    test('logs request and response', () async {
      final logs = <String>[];
      final middleware = LoggingMiddleware(printer: logs.add);

      final response = await middleware.intercept(
        testRequest(Uri.parse('https://example.com/users')),
        const RequestOptions(),
        (request, options) async {
          return testResponse(status: 201);
        },
      );

      expect(response.status, 201);
      expect(logs, hasLength(2));
      expect(logs.first, contains('-> GET https://example.com/users'));
      expect(logs.last, contains('<- 201 GET https://example.com/users'));
    });

    test('logs errors then rethrows', () async {
      final logs = <String>[];
      final middleware = LoggingMiddleware(printer: logs.add);

      await expectLater(
        middleware.intercept(
          testRequest(Uri.parse('https://example.com/fail')),
          const RequestOptions(),
          (request, options) async {
            throw const OxyNetworkException('network down');
          },
        ),
        throwsA(isA<OxyNetworkException>()),
      );

      expect(logs, hasLength(2));
      expect(logs.first, contains('-> GET https://example.com/fail'));
      expect(logs.last, contains('!! GET https://example.com/fail'));
    });
  });
}
