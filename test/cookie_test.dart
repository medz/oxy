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

    test('parseSetCookie parses expires and max-age', () {
      final uri = Uri.parse('https://example.com/login');
      final cookie = parseSetCookie(
        'sid=abc; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Max-Age=120',
        uri,
      );

      expect(cookie.expires, DateTime.utc(2015, 10, 21, 7, 28));
      expect(cookie.maxAge, const Duration(seconds: 120));
    });

    test('toRequestCookie serializes as name=value pair', () {
      const cookie = Cookie('sid', 'abc');

      expect(cookie.toRequestCookie(), 'sid=abc');
    });
  });
}
