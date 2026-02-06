import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('CacheMiddleware', () {
    test('returns fresh cached response without calling downstream', () async {
      final middleware = CacheMiddleware(store: MemoryCacheStore());
      final request = Request(Uri.parse('https://example.com/feed'));

      var callCount = 0;
      Future<Response> downstream(Request req, RequestOptions opt) async {
        callCount += 1;
        return Response.text(
          'network-v1',
          headers: Headers({'cache-control': 'max-age=60', 'etag': '"v1"'}),
        );
      }

      final first = await middleware.intercept(
        request,
        const RequestOptions(),
        downstream,
      );
      expect(await first.text(), 'network-v1');

      final second = await middleware.intercept(
        request,
        const RequestOptions(),
        (req, opt) async {
          callCount += 1;
          return Response.text('network-v2');
        },
      );

      expect(callCount, 1);
      expect(await second.text(), 'network-v1');
    });

    test(
      'revalidates stale cache using if-none-match and handles 304',
      () async {
        final middleware = CacheMiddleware(store: MemoryCacheStore());
        final request = Request(Uri.parse('https://example.com/feed'));

        var callCount = 0;
        Request? revalidationRequest;

        final first = await middleware.intercept(
          request,
          const RequestOptions(),
          (req, opt) async {
            callCount += 1;
            return Response.text(
              'cached-body',
              headers: Headers({
                'cache-control': 'max-age=0',
                'etag': '"tag-1"',
              }),
            );
          },
        );
        expect(await first.text(), 'cached-body');

        final second = await middleware.intercept(
          request,
          const RequestOptions(),
          (req, opt) async {
            callCount += 1;
            revalidationRequest = req;
            return Response(status: 304, headers: Headers({'etag': '"tag-1"'}));
          },
        );

        expect(callCount, 2);
        expect(revalidationRequest?.headers.get('if-none-match'), '"tag-1"');
        expect(second.status, 200);
        expect(await second.text(), 'cached-body');
      },
    );

    test('does not store when cache-control is no-store', () async {
      final middleware = CacheMiddleware(store: MemoryCacheStore());
      final request = Request(Uri.parse('https://example.com/private'));

      var callCount = 0;

      final first = await middleware.intercept(
        request,
        const RequestOptions(),
        (req, opt) async {
          callCount += 1;
          return Response.text(
            'secret-v1',
            headers: Headers({'cache-control': 'no-store'}),
          );
        },
      );
      expect(await first.text(), 'secret-v1');

      final second = await middleware.intercept(
        request,
        const RequestOptions(),
        (req, opt) async {
          callCount += 1;
          return Response.text('secret-v2');
        },
      );

      expect(callCount, 2);
      expect(await second.text(), 'secret-v2');
    });

    test('supports bypass flag via RequestOptions.extra', () async {
      final middleware = CacheMiddleware(store: MemoryCacheStore());
      final request = Request(Uri.parse('https://example.com/feed'));

      var callCount = 0;

      final first = await middleware.intercept(
        request,
        const RequestOptions(),
        (req, opt) async {
          callCount += 1;
          return Response.text(
            'v1',
            headers: Headers({'cache-control': 'max-age=60', 'etag': '"v1"'}),
          );
        },
      );
      expect(await first.text(), 'v1');

      final second = await middleware.intercept(
        request,
        const RequestOptions(extra: {CacheOptionsKeys.bypass: true}),
        (req, opt) async {
          callCount += 1;
          return Response.text('v2');
        },
      );

      expect(callCount, 2);
      expect(await second.text(), 'v2');
    });
  });
}
