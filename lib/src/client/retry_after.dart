import 'package:http_parser/http_parser.dart' show parseHttpDate;

// Normalize only RFC850 to the unambiguous four-digit HTTP-date format. This
// keeps Retry-After independent of when a host applies dependency overlays.
final _rfc850 = RegExp(
  r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), '
  r'(\d{2})-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d{2}) '
  r'(\d{2}:\d{2}:\d{2}) GMT$',
);

/// Internal Retry-After parser; [now] makes the complete 50-year cutoff testable.
DateTime? parseRetryAfterDate(String value, {DateTime? now}) {
  try {
    final match = _rfc850.firstMatch(value);
    if (match == null) return parseHttpDate(value);

    final reference = (now ?? DateTime.now()).toUtc();
    final limit = DateTime.utc(
      reference.year + 50,
      reference.month,
      reference.day,
      reference.hour,
      reference.minute,
      reference.second,
      reference.millisecond,
      reference.microsecond,
    );
    // Select the most recent matching year no later than the full cutoff,
    // including when that cutoff lies in the next century (RFC9110 5.6.7).
    var year = limit.year - limit.year % 100 + int.parse(match[4]!);
    DateTime parseYear() => parseHttpDate(
      '${match[1]!.substring(0, 3)}, ${match[2]} ${match[3]} $year ${match[5]} GMT',
    );
    var date = parseYear();
    if (date.isAfter(limit)) {
      year -= 100;
      date = parseYear();
    }
    return date;
  } on FormatException {
    return DateTime.tryParse(value);
  }
}
