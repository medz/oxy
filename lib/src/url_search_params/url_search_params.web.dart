import 'dart:js_interop';

@JS("URLSearchParams")
extension type URLSearchParams._(JSObject _) {
  @JS("constructor")
  external factory URLSearchParams._internal([JSAny init]);

  /// Create empty URLSearchParams
  factory URLSearchParams() => URLSearchParams._internal();

  /// Parse URLSearchParams from query string
  factory URLSearchParams.parse(String query) =>
      URLSearchParams._internal(query.toJS);

  /// Create URLSearchParams from Map
  factory URLSearchParams.fromMap(Map<String, String> map) {
    final params = URLSearchParams();
    for (final entry in map.entries) {
      params.append(entry.key, entry.value);
    }
    return params;
  }

  /// Get the number of parameters
  external int get size;

  /// Append a parameter
  external void append(String name, String value);

  /// Check if a parameter exists, optionally with a specific value
  external bool has(String name, [String? value]);

  /// Delete parameters by name, optionally by value
  external void delete(String name, [String? value]);

  /// Set a parameter to a single value (replaces all existing values)
  external void set(String name, String value);

  /// Sort parameters by name
  external void sort();

  /// Get the first value for a parameter name
  external String? get(String name);

  /// Convert to query string
  @JS('toString')
  external String stringify();

  /// Get all values for a parameter name
  @JS("getAll")
  external JSArray<JSString> _getAll(String name);
  Iterable<String> getAll(String name) sync* {
    for (final value in _getAll(name).toDart) {
      yield value.toDart;
    }
  }

  /// Get all parameter names in insertion order
  @JS("keys")
  external JSIterator<JSString> _keys();
  Iterable<String> keys() sync* {
    final iterator = _keys();
    while (true) {
      final result = iterator.next();
      if (result.done) break;
      yield result.value.toDart;
    }
  }

  /// Get all parameter values in insertion order
  @JS("values")
  external JSIterator<JSString> _values();
  Iterable<String> values() sync* {
    final iterator = _values();
    while (true) {
      final result = iterator.next();
      if (result.done) break;
      yield result.value.toDart;
    }
  }

  /// Get all parameter entries in insertion order
  @JS("entries")
  external JSIterator<JSArray<JSString>> _entries();
  Iterable<List<String>> entries() sync* {
    final iterator = _entries();
    while (true) {
      final result = iterator.next();
      if (result.done) break;
      final entry = result.value.toDart;
      yield [entry[0].toDart, entry[1].toDart];
    }
  }
}

/// JavaScript Iterator interface for efficient iteration
@JS()
extension type JSIterator<T extends JSAny?>._(JSObject _) implements JSObject {
  external JSIteratorResult<T> next();
}

/// JavaScript Iterator Result interface
@JS()
extension type JSIteratorResult<T extends JSAny?>._(JSObject _)
    implements JSObject {
  external bool get done;
  external T get value;
}
