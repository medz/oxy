import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

void main() {
  test('re-exports ht types', () async {
    final request = Request(
      Uri.parse('https://example.com'),
      headers: Headers({'x-test': '1'}),
    );

    final response = Response.json({
      'ok': true,
    }, headers: Headers({'x-id': '7'}));

    expect(request.method, 'GET');
    expect(request.headers.get('x-test'), '1');
    expect(response.headers.get('x-id'), '7');
    expect(await response.json<Map<String, dynamic>>(), {'ok': true});
  });

  test('fetch options copyWith', () {
    final signal = AbortSignal();
    const options = FetchOptions(timeout: Duration(seconds: 1));
    final next = options.copyWith(
      signal: signal,
      redirect: RedirectPolicy.manual,
    );

    expect(next.signal, same(signal));
    expect(next.redirect, RedirectPolicy.manual);
    expect(next.timeout, const Duration(seconds: 1));
  });
}
