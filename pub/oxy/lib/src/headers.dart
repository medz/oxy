import '_internal/entry_store.dart';

/// A collection of HTTP headers that provides convenient methods for managing
/// header names and values.
///
/// Headers are case-insensitive and can contain multiple values for the same
/// header name. This class provides methods to get, set, append, and delete
/// headers while handling the special case of Set-Cookie headers according
/// to web standards.
///
/// Example:
/// ```dart
/// final headers = Headers();
/// headers.append('Content-Type', 'application/json');
/// headers.append('Accept', 'application/json');
///
/// // Initialize with existing headers
/// final headers2 = Headers({
///   'User-Agent': 'MyApp/1.0',
///   'Accept': 'text/html',
/// });
/// ```
class Headers extends EntryStore<String> {
  /// Creates a new Headers instance.
  ///
  /// If [init] is provided, all key-value pairs from the map will be added
  /// to the headers collection. Header names are treated case-insensitively.
  ///
  /// Example:
  /// ```dart
  /// // Empty headers
  /// final headers = Headers();
  ///
  /// // Headers with initial values
  /// final headers2 = Headers({
  ///   'Content-Type': 'application/json',
  ///   'Authorization': 'Bearer token123',
  /// });
  /// ```
  Headers([Map<String, String>? init]) : super(caseSensitive: false) {
    if (init != null && init.isNotEmpty) {
      for (final MapEntry(:key, :value) in init.entries) {
        append(key, value);
      }
    }
  }

  /// Returns all 'Set-Cookie' header values.
  ///
  /// Set-Cookie headers are treated specially in web standards and cannot be
  /// retrieved using the regular [get] or [getAll] methods. This method provides
  /// access to all Set-Cookie values that have been set.
  ///
  /// This follows the Fetch API specification where Set-Cookie headers are
  /// not exposed through the regular headers interface for security reasons.
  ///
  /// Example:
  /// ```dart
  /// headers.append('Set-Cookie', 'sessionId=abc123; Path=/');
  /// headers.append('Set-Cookie', 'theme=dark; Path=/; Secure');
  ///
  /// final cookies = headers.getSetCookie();
  /// // Returns ['sessionId=abc123; Path=/', 'theme=dark; Path=/; Secure']
  ///
  /// // These would return null/empty:
  /// headers.get('Set-Cookie'); // Returns null
  /// headers.getAll('Set-Cookie'); // Returns []
  /// ```
  Iterable<String> getSetCookie() => getAll('set-cookie');
}
