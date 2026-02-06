import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  group('Cookie', () {
    test('parseSetCookie defaults domain/path from request url', () {
      final uri = Uri.parse('https://api.example.com/users/list');
      final cookie = parseSetCookie('sid=abc123; HttpOnly', uri);

      expect(cookie.name, 'sid');
      expect(cookie.value, 'abc123');
      expect(cookie.domain, 'api.example.com');
      expect(cookie.path, '/users');
      expect(cookie.httpOnly, isTrue);
    });

    test('parseSetCookie applies max-age as relative expiry', () {
      final uri = Uri.parse('https://example.com/login');
      final before = DateTime.now().toUtc();
      final cookie = parseSetCookie(
        'sid=abc; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Max-Age=120',
        uri,
      );

      expect(cookie.maxAge, const Duration(seconds: 120));
      expect(cookie.expires, isNotNull);
      final ttl = cookie.expires!.difference(before).inSeconds;
      expect(ttl, inInclusiveRange(110, 120));
    });

    test('matchesUri enforces path segment boundary', () {
      const cookie = Cookie('sid', 'abc', domain: 'example.com', path: '/foo');

      expect(cookie.matchesUri(Uri.parse('https://example.com/foo')), isTrue);
      expect(
        cookie.matchesUri(Uri.parse('https://example.com/foo/bar')),
        isTrue,
      );
      expect(
        cookie.matchesUri(Uri.parse('https://example.com/foobar')),
        isFalse,
      );
    });

    test('toRequestCookie serializes as name=value pair', () {
      const cookie = Cookie('sid', 'abc');

      expect(cookie.toRequestCookie(), 'sid=abc');
    });
  });
}
