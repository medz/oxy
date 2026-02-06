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

  test('request options copyWith', () {
    final signal = AbortSignal();
    const options = RequestOptions(requestTimeout: Duration(seconds: 1));
    final next = options.copyWith(
      signal: signal,
      redirectPolicy: RedirectPolicy.manual,
      retryPolicy: const RetryPolicy(maxRetries: 5),
    );

    expect(next.signal, same(signal));
    expect(next.redirectPolicy, RedirectPolicy.manual);
    expect(next.requestTimeout, const Duration(seconds: 1));
    expect(next.retryPolicy?.maxRetries, 5);
  });

  test('safeRequest returns OxyFailure instead of throw', () async {
    final client = Oxy();
    final result = await client.safeRequest('GET', '/relative-without-base');

    expect(result.isFailure, isTrue);
    expect(result.error, isA<ArgumentError>());
  });
}
