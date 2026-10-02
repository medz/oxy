import 'package:oxy/oxy.dart';
import 'package:oxy/src/client/retry_after.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 2, 12, 30, 40);
  DateTime? parse(String value, {DateTime? reference}) =>
      parseRetryAfterDate(value, now: reference ?? now);

  test('RFC850 two-digit years work without a patched parser', () {
    expect(
      parse('Friday, 02-Oct-26 12:35:40 GMT'),
      DateTime.utc(2026, 10, 2, 12, 35, 40),
    );
    expect(
      parse('Sunday, 06-Nov-94 08:49:37 GMT'),
      DateTime.utc(1994, 11, 6, 8, 49, 37),
    );
    expect(parse('Tuesday, 29-Feb-00 00:00:00 GMT'), DateTime.utc(2000, 2, 29));
  });

  test(
    'exactly 50 years uses the complete timestamp and an inclusive cutoff',
    () {
      expect(
        parse('Friday, 02-Oct-76 12:30:39 GMT'),
        DateTime.utc(2076, 10, 2, 12, 30, 39),
      );
      expect(
        parse('Friday, 02-Oct-76 12:30:40 GMT'),
        DateTime.utc(2076, 10, 2, 12, 30, 40),
      );
      expect(
        parse('Friday, 02-Oct-76 12:30:41 GMT'),
        DateTime.utc(1976, 10, 2, 12, 30, 41),
      );
      expect(
        parse('Thursday, 01-Oct-76 23:59:59 GMT'),
        DateTime.utc(2076, 10, 1, 23, 59, 59),
      );
      expect(
        parse('Saturday, 03-Oct-76 00:00:00 GMT'),
        DateTime.utc(1976, 10, 3),
      );
      expect(
        parse(
          'Friday, 02-Oct-76 12:30:40 GMT',
          reference: now.subtract(const Duration(microseconds: 1)),
        ),
        DateTime.utc(1976, 10, 2, 12, 30, 40),
      );
      expect(
        parse(
          'Friday, 02-Oct-76 12:30:40 GMT',
          reference: now.add(const Duration(microseconds: 1)),
        ),
        DateTime.utc(2076, 10, 2, 12, 30, 40),
      );
    },
  );

  test('the two-digit window also works across century boundaries', () {
    expect(
      parse('Friday, 02-Oct-26 12:35:40 GMT', reference: DateTime.utc(1999)),
      DateTime.utc(2026, 10, 2, 12, 35, 40),
    );
    expect(
      parse('Friday, 01-Jan-00 00:00:00 GMT', reference: DateTime.utc(2090)),
      DateTime.utc(2100),
    );
    expect(
      parse('Friday, 01-Jan-99 00:00:00 GMT', reference: DateTime.utc(2101)),
      DateTime.utc(2099),
    );
  });

  test('RFC1123, asctime and existing ISO fallback keep their own years', () {
    expect(
      parse('Fri, 02 Oct 2077 12:30:40 GMT'),
      DateTime.utc(2077, 10, 2, 12, 30, 40),
    );
    expect(
      parse('Fri Oct  2 12:30:40 2077'),
      DateTime.utc(2077, 10, 2, 12, 30, 40),
    );
    expect(parse('2026-10-02T12:30:40Z'), now);
  });

  test('invalid RFC850 values do not become valid through normalization', () {
    for (final date in [
      'Friday, 31-Apr-26 12:30:40 GMT',
      'Friday, 29-Feb-26 12:30:40 GMT',
      'Friday, 00-Oct-26 12:30:40 GMT',
      'Friday, 02-Oct-26 24:30:40 GMT',
      'Friday, 02-Oct-26 12:60:40 GMT',
      'Friday, 02-Oct-26 12:30:60 GMT',
      'Friday, 02-Nope-26 12:30:40 GMT',
      'Friday, 02-Oct-026 12:30:40 GMT',
      'Friday, 02-Oct-26 12:30:40 GMT trailing',
      'friday, 02-Oct-26 12:30:40 GMT',
    ]) {
      expect(parse(date), isNull, reason: date);
      final delay =
          const RetryPolicy(
            baseDelay: Duration(milliseconds: 100),
            jitterRatio: 0,
          ).delayFor(
            0,
            response: Response.text(
              'busy',
              status: 503,
              headers: {'retry-after': date},
            ),
          );
      expect(delay, const Duration(milliseconds: 100), reason: date);
    }
  });

  test('numeric Retry-After and disabling respectRetryAfter are unchanged', () {
    final response = Response.text(
      'busy',
      status: 503,
      headers: {'retry-after': ' 120 '},
    );
    expect(
      const RetryPolicy().delayFor(0, response: response),
      const Duration(seconds: 120),
    );
    expect(
      const RetryPolicy(
        respectRetryAfter: false,
        jitterRatio: 0,
      ).delayFor(0, response: response),
      const Duration(milliseconds: 200),
    );
  });
}
