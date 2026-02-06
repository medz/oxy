import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('RequestIdMiddleware', () {
    test('adds request id header from provider', () async {
      final middleware = RequestIdMiddleware(
        requestIdProvider: (_, _) => 'req-123',
      );

      late Request captured;
      await middleware.intercept(
        Request(Uri.parse('https://example.com')),
        const RequestOptions(),
        (nextRequest, options) async {
          captured = nextRequest;
          return Response();
        },
      );

      expect(captured.headers.get('x-request-id'), 'req-123');
    });

    test('does not override existing header by default', () async {
      final middleware = RequestIdMiddleware(
        requestIdProvider: (_, _) => 'req-new',
      );

      late Request captured;
      await middleware.intercept(
        Request(
          Uri.parse('https://example.com'),
          headers: Headers({'x-request-id': 'req-old'}),
        ),
        const RequestOptions(),
        (nextRequest, options) async {
          captured = nextRequest;
          return Response();
        },
      );

      expect(captured.headers.get('x-request-id'), 'req-old');
    });

    test('overrides existing header when configured', () async {
      final middleware = RequestIdMiddleware(
        requestIdProvider: (_, _) => 'req-new',
        overrideExisting: true,
      );

      late Request captured;
      await middleware.intercept(
        Request(
          Uri.parse('https://example.com'),
          headers: Headers({'x-request-id': 'req-old'}),
        ),
        const RequestOptions(),
        (nextRequest, options) async {
          captured = nextRequest;
          return Response();
        },
      );

      expect(captured.headers.get('x-request-id'), 'req-new');
    });

    test('skips header when provider returns null', () async {
      final middleware = RequestIdMiddleware(requestIdProvider: (_, _) => null);

      late Request captured;
      await middleware.intercept(
        Request(Uri.parse('https://example.com')),
        const RequestOptions(),
        (nextRequest, options) async {
          captured = nextRequest;
          return Response();
        },
      );

      expect(captured.headers.has('x-request-id'), isFalse);
    });

    test('skips header when provider returns blank value', () async {
      final middleware = RequestIdMiddleware(
        requestIdProvider: (_, _) => '   ',
      );

      late Request captured;
      await middleware.intercept(
        Request(Uri.parse('https://example.com')),
        const RequestOptions(),
        (nextRequest, options) async {
          captured = nextRequest;
          return Response();
        },
      );

      expect(captured.headers.has('x-request-id'), isFalse);
    });
  });
}
