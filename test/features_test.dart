import 'dart:async';

import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';
import 'package:test/test.dart';

final class CapabilityTransport implements Transport {
  CapabilityTransport(this.capability, this._responder);

  @override
  final PlatformCapability capability;

  final Future<Response> Function(Request request, Context context) _responder;

  @override
  Future<void> close() async {}

  @override
  Future<Response> send(Request request, Context context) {
    return _responder(request, context);
  }
}

void main() {
  test('auth and request id middleware modify immutable requests', () async {
    late Request captured;
    final client = Client(
      ClientOptions(
        transport: MockTransport((request, context) async {
          captured = request;
          return Response.text('ok');
        }),
        middleware: [
          AuthMiddleware.staticToken('abc'),
          RequestIdMiddleware(requestIdProvider: (_, _) => 'rid'),
        ],
      ),
    );

    await client.get('https://example.com');

    expect(captured.headers.get('authorization'), 'Bearer abc');
    expect(captured.headers.get('x-request-id'), 'rid');
  });

  test('cookie middleware isolates cookie state in client-owned jar', () async {
    final jar = MemoryCookieJar();
    var calls = 0;
    late Request secondRequest;
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 2) {
            secondRequest = request;
          }
          return Response.text(
            'ok',
            headers: calls == 1
                ? Headers({'set-cookie': 'sid=abc; Path=/; HttpOnly'})
                : null,
          );
        }),
      ),
    );

    await client.get('https://example.com/login');
    await client.get('https://example.com/profile');

    expect(secondRequest.headers.get('cookie'), 'sid=abc');
    expect(
      await jar.load(Uri.parse('https://sub.example.com/profile')),
      isEmpty,
    );
  });

  test('cookie middleware preserves duplicate path-scoped cookies', () async {
    final jar = MemoryCookieJar();
    await jar.save(Uri.parse('https://example.com/login'), [
      const Cookie('sid', 'root', path: '/'),
    ]);
    await jar.save(Uri.parse('https://example.com/app/login'), [
      const Cookie('sid', 'app', path: '/app'),
    ]);

    late Request captured;
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: MockTransport((request, context) async {
          captured = request;
          return Response.text('ok');
        }),
      ),
    );

    await client.get('https://example.com/app/page');

    expect(captured.headers.get('cookie'), 'sid=app; sid=root');
  });

  test('cookie jar enforces domain and host-only scoping', () async {
    final jar = MemoryCookieJar();
    await jar.save(Uri.parse('https://example.com/login'), [
      const Cookie('sid', 'host', path: '/'),
    ]);
    await jar.save(Uri.parse('https://api.example.com/login'), [
      const Cookie('wide', 'domain', domain: 'example.com', path: '/'),
    ]);

    final rootCookies = await jar.load(Uri.parse('https://example.com/home'));
    final subdomainCookies = await jar.load(
      Uri.parse('https://sub.example.com/home'),
    );

    expect(rootCookies.map((cookie) => cookie.name), contains('sid'));
    final rootSid = rootCookies.singleWhere((cookie) => cookie.name == 'sid');
    expect(rootSid.domain, isNull);
    expect(rootSid.matchesUri(Uri.parse('https://example.com/home')), isFalse);
    expect(
      subdomainCookies.map((cookie) => cookie.name),
      isNot(contains('sid')),
    );
    expect(subdomainCookies.map((cookie) => cookie.name), contains('wide'));
    await expectLater(
      jar.save(Uri.parse('https://evil.example/login'), [
        const Cookie('attack', '1', domain: 'victim.example', path: '/'),
      ]),
      throwsArgumentError,
    );
    await expectLater(
      jar.save(Uri.parse('https://api.example.com/login'), [
        const Cookie('attack', '1', domain: 'com', path: '/'),
      ]),
      throwsArgumentError,
    );
  });

  test('standalone host-only parsed cookies fail closed for URI matching', () {
    final cookie = parseSetCookie(
      'sid=abc; Path=/; HttpOnly',
      Uri.parse('https://example.com/login'),
    );

    expect(cookie.domain, isNull);
    expect(
      cookie.matchesUri(Uri.parse('https://example.com/profile')),
      isFalse,
    );
    expect(
      cookie.matchesUri(Uri.parse('https://other.example/profile')),
      isFalse,
    );
  });

  test('cookie middleware stores response cookies against final URL', () async {
    final jar = MemoryCookieJar();
    var calls = 0;
    late Request finalHostRequest;
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            return Response.text(
              'redirected',
              headers: Headers({'set-cookie': 'sid=final; Path=/'}),
              url: Uri.parse('https://b.example.com/final'),
            );
          }
          finalHostRequest = request;
          return Response.text('ok');
        }),
      ),
    );

    await client.get('https://a.example.com/start');
    await client.get('https://b.example.com/account');

    expect(finalHostRequest.headers.get('cookie'), 'sid=final');
    expect(await jar.load(Uri.parse('https://a.example.com/account')), isEmpty);
  });

  test('cookie middleware stores cookies from followed redirects', () async {
    final jar = MemoryCookieJar();
    var calls = 0;
    late Request finalRequest;
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 1) {
            return Response(
              null,
              status: 302,
              headers: {
                'location': '/account',
                'set-cookie': 'sid=redirect; Path=/',
              },
            );
          }
          finalRequest = request;
          return Response.text('ok', url: request.uri);
        }),
      ),
    );

    final response = await client.get('https://example.com/login');

    expect(await response.text(), 'ok');
    expect(response.redirected, isTrue);
    expect(finalRequest.headers.get('cookie'), 'sid=redirect');
    expect(calls, 2);
  });

  test(
    'cookie middleware rehydrates cookies for cross-origin redirects',
    () async {
      final jar = MemoryCookieJar();
      await jar.save(Uri.parse('https://example.com'), [
        const Cookie('sid', 'source', path: '/'),
      ]);
      await jar.save(Uri.parse('https://other.example'), [
        const Cookie('sid', 'target', path: '/'),
      ]);

      var calls = 0;
      late Request redirected;
      final client = Client(
        ClientOptions(
          middleware: [CookieMiddleware(jar)],
          transport: MockTransport((request, context) async {
            calls += 1;
            if (calls == 1) {
              expect(request.headers.get('cookie'), 'sid=source');
              return Response(
                null,
                status: 302,
                headers: {'location': 'https://other.example/account'},
                url: request.uri,
              );
            }
            redirected = request;
            return Response.text('ok', url: request.uri);
          }),
        ),
      );

      await client.get('https://example.com/login');

      expect(redirected.headers.get('cookie'), 'sid=target');
    },
  );

  test('cookie middleware stores cookies from status errors', () async {
    final jar = MemoryCookieJar();
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: MockTransport((request, context) async {
          return Response.text(
            'unauthorized',
            status: 401,
            headers: {'set-cookie': 'sid=error; Path=/'},
            url: request.uri,
          );
        }),
      ),
    );

    await expectLater(
      client.get('https://example.com/login'),
      throwsA(isA<StatusError>()),
    );

    final cookies = await jar.load(Uri.parse('https://example.com/account'));
    expect(cookies.map((cookie) => cookie.name), contains('sid'));
  });

  test('cookie middleware is a no-op for browser transports', () async {
    final jar = MemoryCookieJar();
    await jar.save(Uri.parse('https://example.com'), [
      const Cookie('sid', 'abc', path: '/'),
    ]);
    late Request captured;
    final client = Client(
      ClientOptions(
        middleware: [CookieMiddleware(jar)],
        transport: CapabilityTransport(PlatformCapability.web, (
          request,
          context,
        ) async {
          captured = request;
          return Response.text(
            'ok',
            headers: Headers({'set-cookie': 'ignored=1'}),
          );
        }),
      ),
    );

    await client.get('https://example.com');

    expect(captured.headers.has('cookie'), isFalse);
    expect(await jar.load(Uri.parse('https://example.com')), hasLength(1));
  });

  test('cache middleware reuses fresh buffered responses', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text(
            'v$calls',
            headers: Headers({'cache-control': 'max-age=60'}),
          );
        }),
      ),
    );

    final first = await client.get('https://example.com/feed');
    final second = await client.get('https://example.com/feed');

    expect(await first.text(), 'v1');
    expect(await second.text(), 'v1');
    expect(first.fromCache, isFalse);
    expect(second.fromCache, isTrue);
    expect(calls, 1);
  });

  test('cache middleware treats aged max-age responses as stale', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text(
            'v$calls',
            headers: {'cache-control': 'max-age=60', 'age': '120'},
          );
        }),
      ),
    );

    final first = await client.get('https://example.com/feed');
    final second = await client.get('https://example.com/feed');

    expect(await first.text(), 'v1');
    expect(await second.text(), 'v2');
    expect(second.fromCache, isFalse);
    expect(calls, 2);
  });

  test(
    'cache middleware revalidates entries older than request max-age',
    () async {
      final store = MemoryCacheStore();
      final now = DateTime.now().toUtc();
      await store.write(
        'feed',
        CachedResponse(
          response: Response.text(
            'cached',
            headers: {'cache-control': 'max-age=3600'},
          ),
          storedAt: now.subtract(const Duration(seconds: 120)),
          expiresAt: now.add(const Duration(seconds: 3600)),
          etag: null,
        ),
      );

      var calls = 0;
      final client = Client(
        ClientOptions(
          middleware: [
            CacheMiddleware(store: store, keyBuilder: (_, _) => 'feed'),
          ],
          transport: MockTransport((request, context) async {
            calls += 1;
            return Response.text(
              'fresh',
              headers: {'cache-control': 'max-age=3600'},
            );
          }),
        ),
      );

      final response = await client.get(
        'https://example.com/feed',
        headers: {'cache-control': 'max-age=60'},
      );

      expect(await response.text(), 'fresh');
      expect(response.fromCache, isFalse);
      expect(calls, 1);
    },
  );

  test(
    'cache middleware counts response Age against request max-age',
    () async {
      var calls = 0;
      final client = Client(
        ClientOptions(
          middleware: [CacheMiddleware()],
          transport: MockTransport((request, context) async {
            calls += 1;
            return Response.text(
              'v$calls',
              headers: {
                'cache-control': 'max-age=300',
                'age': calls == 1 ? '120' : '0',
              },
            );
          }),
        ),
      );

      expect(await (await client.get('https://example.com/feed')).text(), 'v1');
      final second = await client.get(
        'https://example.com/feed',
        headers: {'cache-control': 'max-age=60'},
      );

      expect(await second.text(), 'v2');
      expect(second.fromCache, isFalse);
      expect(calls, 2);
    },
  );

  test('cache middleware keys request header variants', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text(
            request.headers.get('authorization') ?? 'none',
            headers: Headers({
              'cache-control': 'max-age=60',
              'vary': 'Authorization',
            }),
          );
        }),
      ),
    );

    final first = await client.get(
      'https://example.com/me',
      headers: {'authorization': 'Bearer a'},
    );
    final second = await client.get(
      'https://example.com/me',
      headers: {'authorization': 'Bearer b'},
    );

    expect(await first.text(), 'Bearer a');
    expect(await second.text(), 'Bearer b');
    expect(calls, 2);
  });

  test('cache middleware ignores generated request ids by default', () async {
    var calls = 0;
    var requestIds = 0;
    final client = Client(
      ClientOptions(
        middleware: [
          RequestIdMiddleware(
            requestIdProvider: (_, _) => 'rid-${requestIds++}',
          ),
          CacheMiddleware(),
        ],
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text(
            'cached',
            headers: {'cache-control': 'max-age=60'},
          );
        }),
      ),
    );

    expect(
      await (await client.get('https://example.com/feed')).text(),
      'cached',
    );
    final second = await client.get('https://example.com/feed');

    expect(await second.text(), 'cached');
    expect(second.fromCache, isTrue);
    expect(calls, 1);
  });

  test('cache middleware revalidates request and response no-cache', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (request.headers.get('if-none-match') == 'v1') {
            return Response(null, status: 304, headers: {'etag': 'v1'});
          }
          return Response.text(
            'fresh',
            headers: Headers({
              'cache-control': 'no-cache, max-age=60',
              'etag': 'v1',
            }),
          );
        }),
      ),
    );

    expect(
      await (await client.get('https://example.com/feed')).text(),
      'fresh',
    );
    final second = await client.get(
      'https://example.com/feed',
      headers: {'cache-control': 'max-age=0'},
    );

    expect(await second.text(), 'fresh');
    expect(second.fromCache, isTrue);
    expect(calls, 2);
  });

  test('cache middleware honors request no-store', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text(
            'v$calls',
            headers: Headers({'cache-control': 'max-age=60'}),
          );
        }),
      ),
    );

    expect(await (await client.get('https://example.com/feed')).text(), 'v1');
    final second = await client.get(
      'https://example.com/feed',
      headers: {'cache-control': 'no-store'},
    );

    expect(await second.text(), 'v2');
    expect(second.fromCache, isFalse);
    expect(calls, 2);
  });

  test('cache middleware honors request pragma no-cache', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          return Response.text(
            'v$calls',
            headers: {'cache-control': 'max-age=60'},
          );
        }),
      ),
    );

    expect(await (await client.get('https://example.com/feed')).text(), 'v1');
    final second = await client.get(
      'https://example.com/feed',
      headers: {'pragma': 'no-cache'},
    );

    expect(await second.text(), 'v2');
    expect(second.fromCache, isFalse);
    expect(calls, 2);
  });

  test('cache middleware revalidates caller conditional requests', () async {
    var calls = 0;
    String? conditionalHeader;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 2) {
            conditionalHeader = request.headers.get('if-none-match');
            return Response(null, status: 304, headers: {'etag': 'v1'});
          }
          return Response.text(
            'cached',
            headers: {'cache-control': 'max-age=60', 'etag': 'v1'},
          );
        }),
      ),
    );

    expect(
      await (await client.get('https://example.com/feed')).text(),
      'cached',
    );
    final second = await client.get(
      'https://example.com/feed',
      headers: {'if-none-match': 'v1'},
    );

    expect(await second.text(), 'cached');
    expect(second.fromCache, isTrue);
    expect(conditionalHeader, 'v1');
    expect(calls, 2);
  });

  test('cache middleware weakly matches caller etag validators', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 2) {
            expect(request.headers.get('if-none-match'), 'W/"v1"');
            return Response(null, status: 304, headers: {'etag': '"v1"'});
          }
          return Response.text(
            'cached-v1',
            headers: {'cache-control': 'max-age=60', 'etag': '"v1"'},
          );
        }),
      ),
    );

    expect(
      await (await client.get('https://example.com/feed')).text(),
      'cached-v1',
    );
    final second = await client.get(
      'https://example.com/feed',
      headers: {'if-none-match': 'W/"v1"'},
    );

    expect(await second.text(), 'cached-v1');
    expect(second.fromCache, isTrue);
    expect(calls, 2);
  });

  test('cache middleware does not merge wildcard 304 validators', () async {
    var calls = 0;
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          calls += 1;
          if (calls == 2) {
            expect(request.headers.get('if-none-match'), '*');
            return Response(null, status: 304, headers: {'etag': '"v2"'});
          }
          return Response.text(
            'cached-v1',
            headers: {'cache-control': 'max-age=60', 'etag': '"v1"'},
          );
        }),
      ),
    );

    expect(
      await (await client.get('https://example.com/feed')).text(),
      'cached-v1',
    );
    final second = await client.get(
      'https://example.com/feed',
      headers: {'if-none-match': '*'},
    );

    expect(second.status, 304);
    expect(second.fromCache, isFalse);
    expect(calls, 2);
  });

  test(
    'cache middleware does not merge unrelated caller 304 validators',
    () async {
      var calls = 0;
      final client = Client(
        ClientOptions(
          middleware: [CacheMiddleware()],
          transport: MockTransport((request, context) async {
            calls += 1;
            if (calls == 2) {
              expect(request.headers.get('if-none-match'), 'v2');
              return Response(null, status: 304, headers: {'etag': 'v2'});
            }
            return Response.text(
              'cached-v1',
              headers: {'cache-control': 'max-age=60', 'etag': 'v1'},
            );
          }),
        ),
      );

      expect(
        await (await client.get('https://example.com/feed')).text(),
        'cached-v1',
      );
      final second = await client.get(
        'https://example.com/feed',
        headers: {'if-none-match': 'v2'},
      );

      expect(second.status, 304);
      expect(second.fromCache, isFalse);
      expect(calls, 2);
    },
  );

  test('cache middleware surfaces stream buffering failures', () async {
    final client = Client(
      ClientOptions(
        middleware: [CacheMiddleware()],
        transport: MockTransport((request, context) async {
          return Response.stream(
            Stream<List<int>>.error(StateError('broken stream')),
            headers: {'cache-control': 'max-age=60'},
          );
        }),
      ),
    );

    await expectLater(
      client.get('https://example.com/broken'),
      throwsA(
        isA<NetworkError>().having(
          (error) => error.cause,
          'cause',
          isA<StateError>(),
        ),
      ),
    );
  });

  test(
    'cache middleware skips oversized entries without failing response',
    () async {
      final large = List.filled(32, 'x').join();
      var calls = 0;
      final client = Client(
        ClientOptions(
          middleware: [CacheMiddleware(maxEntryBytes: 8)],
          transport: MockTransport((request, context) async {
            calls += 1;
            return Response.stream(
              Stream<List<int>>.value(large.codeUnits),
              headers: Headers({'cache-control': 'max-age=60'}),
            );
          }),
        ),
      );

      final response = await client.get('https://example.com/large');

      expect(await response.text(), large);
      expect(response.fromCache, isFalse);
      expect(calls, 1);
    },
  );

  test('presets remain single-package feature composition', () {
    final middleware = Presets.full(auth: AuthMiddleware.staticToken('token'));

    expect(middleware[0], isA<RequestIdMiddleware>());
    expect(middleware[1], isA<AuthMiddleware>());
    expect(middleware[2], isA<CookieMiddleware>());
    expect(middleware[3], isA<CacheMiddleware>());
    expect(middleware[4], isA<LoggingMiddleware>());
  });

  test('logging middleware redacts userinfo query and fragment', () async {
    final messages = <String>[];
    final client = Client(
      ClientOptions(
        middleware: [LoggingMiddleware(printer: messages.add)],
        transport: MockTransport((request, context) async {
          return Response.text('ok');
        }),
      ),
    );

    await client.get('https://user:pass@example.com/feed?token=secret#frag');

    expect(messages, isNotEmpty);
    expect(messages.first, contains('https://%3Credacted%3E@example.com/feed'));
    expect(messages.first, contains('?%3Credacted%3E'));
    expect(messages.first, contains('#%3Credacted%3E'));
    expect(messages.first, isNot(contains('user:pass')));
    expect(messages.first, isNot(contains('secret')));
    expect(messages.first, isNot(contains('frag')));
  });

  test('exports complete cookie copy API', () {
    const cookie = Cookie('sid', 'abc', domain: 'example.com');
    final hostOnly = cookie.copyWith(clear: const {CookieNullableField.domain});

    expect(hostOnly.domain, isNull);
  });
}
