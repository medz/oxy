/// Extension for efficient string operations in URLSearchParams
extension on String {
  /// Safely decode URL query component, fallback to original string on error
  String tryDecodeQueryComponent() {
    try {
      return Uri.decodeQueryComponent(this);
    } catch (_) {
      return this;
    }
  }

  /// Safely encode URL query component, fallback to original string on error
  /// Uses percent encoding where spaces become %20 (not +)
  String tryEncodeQueryComponent() {
    try {
      // Use Uri.encodeComponent instead of encodeQueryComponent
      // to ensure spaces are encoded as %20, not +
      return Uri.encodeComponent(this);
    } catch (_) {
      return this;
    }
  }

  /// Remove leading question marks from query string
  String _removeLeadingQuestionMarks() {
    var start = 0;
    while (start < length && this[start] == '?') {
      start++;
    }
    return start == 0 ? this : substring(start);
  }
}

/// Internal storage for URLSearchParams that maintains insertion order
/// while providing efficient operations
final class _URLSearchParamsStore {
  /// Map for O(1) lookups - maps name to list of values
  final Map<String, List<String>> _paramMap = <String, List<String>>{};

  /// List to maintain insertion order for iteration
  final List<(String, String)> _insertionOrder = <(String, String)>[];

  /// Cached string representation
  String? _cachedString;

  /// Whether the cached string is dirty
  bool _isDirty = true;

  /// Constructor for empty params
  _URLSearchParamsStore();

  /// Constructor from parsed entries
  _URLSearchParamsStore.fromEntries(List<(String, String)> entries) {
    for (final (name, value) in entries) {
      _addEntry(name, value);
    }
    _isDirty = true;
  }

  /// Add an entry without marking dirty (for batch operations)
  void _addEntry(String name, String value) {
    (_paramMap[name] ??= <String>[]).add(value);
    _insertionOrder.add((name, value));
  }

  /// Mark the cached string as dirty
  void _markDirty() {
    _isDirty = true;
    _cachedString = null;
  }

  /// Get the number of parameters
  int get size => _insertionOrder.length;

  /// Check if empty
  bool get isEmpty => _insertionOrder.isEmpty;

  /// Append a parameter
  void append(String name, String value) {
    _addEntry(name, value);
    _markDirty();
  }

  /// Delete parameters by name, optionally by value
  void delete(String name, [String? value]) {
    final values = _paramMap[name];
    if (values == null) return;

    if (value == null) {
      // Remove all entries with this name
      _paramMap.remove(name);
      _insertionOrder.removeWhere((entry) => entry.$1 == name);
    } else {
      // Remove only entries with matching name and value
      values.remove(value);
      if (values.isEmpty) {
        _paramMap.remove(name);
      }
      _insertionOrder.removeWhere(
        (entry) => entry.$1 == name && entry.$2 == value,
      );
    }
    _markDirty();
  }

  /// Get the first value for a parameter name
  String? get(String name) {
    final values = _paramMap[name];
    return values?.isNotEmpty == true ? values!.first : null;
  }

  /// Get all values for a parameter name
  List<String> getAll(String name) {
    return _paramMap[name]?.toList() ?? <String>[];
  }

  /// Check if a parameter exists, optionally with a specific value
  bool has(String name, [String? value]) {
    final values = _paramMap[name];
    if (values == null || values.isEmpty) return false;

    if (value == null) return true;
    return values.contains(value);
  }

  /// Set a parameter to a single value (replaces all existing values)
  void set(String name, String value) {
    // Remove all existing entries with this name
    final oldValues = _paramMap[name];
    if (oldValues != null) {
      _insertionOrder.removeWhere((entry) => entry.$1 == name);
    }

    // Set new value
    _paramMap[name] = [value];
    _insertionOrder.add((name, value));
    _markDirty();
  }

  /// Sort parameters by name
  void sort() {
    // Rebuild both structures in sorted order
    _insertionOrder.sort((a, b) => a.$1.compareTo(b.$1));

    // Rebuild the map to maintain consistency
    _paramMap.clear();
    for (final (name, value) in _insertionOrder) {
      (_paramMap[name] ??= <String>[]).add(value);
    }
    _markDirty();
  }

  /// Get all parameter names in insertion order
  Iterable<String> keys() sync* {
    final seen = <String>{};
    for (final (name, _) in _insertionOrder) {
      if (seen.add(name)) {
        yield name;
      }
    }
  }

  /// Get all parameter values in insertion order
  Iterable<String> values() sync* {
    for (final (_, value) in _insertionOrder) {
      yield value;
    }
  }

  /// Get all parameter entries in insertion order
  Iterable<(String, String)> entries() => _insertionOrder;

  /// Convert to query string
  String stringify() {
    if (_insertionOrder.isEmpty) return '';

    if (_isDirty || _cachedString == null) {
      final buffer = StringBuffer();
      var first = true;

      for (final (name, value) in _insertionOrder) {
        if (!first) buffer.write('&');
        first = false;

        buffer.write(name.tryEncodeQueryComponent());
        buffer.write('=');
        buffer.write(value.tryEncodeQueryComponent());
      }

      _cachedString = buffer.toString();
      _isDirty = false;
    }

    return _cachedString!;
  }
}

/// URLSearchParams implementation for native platform
extension type URLSearchParams._(_URLSearchParamsStore _store) {
  /// Create empty URLSearchParams
  factory URLSearchParams() => URLSearchParams._(_URLSearchParamsStore());

  /// Parse URLSearchParams from query string
  factory URLSearchParams.parse(String query) {
    return URLSearchParams._(_parseQueryString(query));
  }

  /// Create URLSearchParams from Map
  factory URLSearchParams.fromMap(Map<String, String> source) {
    final store = _URLSearchParamsStore();
    for (final entry in source.entries) {
      store.append(entry.key, entry.value);
    }
    return URLSearchParams._(store);
  }

  /// Parse a query string into URLSearchParams store
  static _URLSearchParamsStore _parseQueryString(String query) {
    if (query.isEmpty) return _URLSearchParamsStore();

    // Remove leading question marks
    query = query._removeLeadingQuestionMarks();
    if (query.isEmpty) return _URLSearchParamsStore();

    final entries = <(String, String)>[];

    // Split by & and process each parameter
    for (final param in query.split('&')) {
      if (param.isEmpty) continue;

      final eqIndex = param.indexOf('=');
      final String name, value;

      if (eqIndex == -1) {
        // No = found, treat entire string as name with empty value
        name = param.tryDecodeQueryComponent();
        value = '';
      } else {
        // Split on first = only
        name = param.substring(0, eqIndex).tryDecodeQueryComponent();
        value = param.substring(eqIndex + 1).tryDecodeQueryComponent();
      }

      // Only add non-empty names (following Web Standards)
      if (name.isNotEmpty) {
        entries.add((name, value));
      }
    }

    return _URLSearchParamsStore.fromEntries(entries);
  }

  /// Get the number of parameters
  int get size => _store.size;

  /// Append a parameter
  void append(String name, String value) => _store.append(name, value);

  /// Delete parameters by name, optionally by value
  void delete(String name, [String? value]) => _store.delete(name, value);

  /// Get the first value for a parameter name
  String? get(String name) => _store.get(name);

  /// Get all values for a parameter name
  Iterable<String> getAll(String name) => _store.getAll(name);

  /// Check if a parameter exists, optionally with a specific value
  bool has(String name, [String? value]) => _store.has(name, value);

  /// Set a parameter to a single value (replaces all existing values)
  void set(String name, String value) => _store.set(name, value);

  /// Sort parameters by name
  void sort() => _store.sort();

  /// Get all parameter names in insertion order
  Iterable<String> keys() => _store.keys();

  /// Get all parameter values in insertion order
  Iterable<String> values() => _store.values();

  /// Get all parameter entries in insertion order
  Iterable<List<String>> entries() sync* {
    for (final (name, value) in _store.entries()) {
      yield [name, value];
    }
  }

  /// Convert to query string
  String stringify() => _store.stringify();
}
