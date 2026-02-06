import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('AuthMiddleware', () {
    test('adds authorization header from static token', () async {
      final middleware = AuthMiddleware.staticToken('abc123');
      final request = Request(Uri.parse('https://example.com'));

      late Request captured;
      await middleware.intercept(request, const RequestOptions(), (
        nextRequest,
        options,
      ) async {
        captured = nextRequest;
        return Response();
      });

      expect(captured.headers.get('authorization'), 'Bearer abc123');
    });

    test('does not override existing header by default', () async {
      final middleware = AuthMiddleware.staticToken('abc123');
      final request = Request(
        Uri.parse('https://example.com'),
        headers: Headers({'authorization': 'Bearer existing'}),
      );

      late Request captured;
      await middleware.intercept(request, const RequestOptions(), (
        nextRequest,
        options,
      ) async {
        captured = nextRequest;
        return Response();
      });

      expect(captured.headers.get('authorization'), 'Bearer existing');
    });

    test('overrides existing header when configured', () async {
      final middleware = AuthMiddleware.staticToken(
        'new-token',
        overrideExisting: true,
      );
      final request = Request(
        Uri.parse('https://example.com'),
        headers: Headers({'authorization': 'Bearer old-token'}),
      );

      late Request captured;
      await middleware.intercept(request, const RequestOptions(), (
        nextRequest,
        options,
      ) async {
        captured = nextRequest;
        return Response();
      });

      expect(captured.headers.get('authorization'), 'Bearer new-token');
    });

    test('supports no scheme mode', () async {
      final middleware = AuthMiddleware.staticToken('raw-token', scheme: null);
      final request = Request(Uri.parse('https://example.com'));

      late Request captured;
      await middleware.intercept(request, const RequestOptions(), (
        nextRequest,
        options,
      ) async {
        captured = nextRequest;
        return Response();
      });

      expect(captured.headers.get('authorization'), 'raw-token');
    });

    test('skips header when provider returns null', () async {
      final middleware = AuthMiddleware(tokenProvider: (_, _) => null);
      final request = Request(Uri.parse('https://example.com'));

      late Request captured;
      await middleware.intercept(request, const RequestOptions(), (
        nextRequest,
        options,
      ) async {
        captured = nextRequest;
        return Response();
      });

      expect(captured.headers.has('authorization'), isFalse);
    });
  });
}
