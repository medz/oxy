/// Inputs accepted by [Headers].
typedef HeadersInit = Object?;

/// Case-insensitive HTTP headers with multi-value support.
///
/// Header names are normalized to lowercase. `set-cookie` is kept as separate
/// values through [getAll] and [getSetCookie].
final class Headers with Iterable<MapEntry<String, String>> {
  Headers([HeadersInit init]) {
    _fill(init);
  }

  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  Iterator<MapEntry<String, String>> get iterator => _entries().iterator;

  Iterable<MapEntry<String, String>> _entries() sync* {
    for (final entry in _values.entries) {
      for (final value in entry.value) {
        yield MapEntry<String, String>(entry.key, value);
      }
    }
  }

  @override
  bool get isEmpty => _values.isEmpty;
  @override
  bool get isNotEmpty => _values.isNotEmpty;

  /// Appends [value] to [name].
  void append(String name, Object value) {
    final key = _normalizeName(name);
    final text = value.toString();
    _values.putIfAbsent(key, () => <String>[]).add(text);
  }

  /// Replaces all values for [name] with [value].
  void set(String name, Object value) {
    _values[_normalizeName(name)] = <String>[value.toString()];
  }

  /// Removes all values for [name].
  void delete(String name) {
    _values.remove(_normalizeName(name));
  }

  /// Whether [name] is present.
  bool has(String name) {
    return _values.containsKey(_normalizeName(name));
  }

  /// The comma-joined value for [name], or `null`.
  ///
  /// For `set-cookie`, values are joined with newlines to avoid comma parsing
  /// ambiguity. Prefer [getSetCookie] for cookie handling.
  String? get(String name) {
    final values = _values[_normalizeName(name)];
    if (values == null || values.isEmpty) {
      return null;
    }

    return values.join(_normalizeName(name) == 'set-cookie' ? '\n' : ',');
  }

  /// All values for [name].
  List<String> getAll(String name) {
    return List<String>.unmodifiable(_values[_normalizeName(name)] ?? const []);
  }

  /// All `set-cookie` header values.
  List<String> getSetCookie() => getAll('set-cookie');

  /// The normalized header names.
  Iterable<String> keys() => _values.keys;

  /// A mutable copy of these headers.
  Headers copy() => Headers(this);

  /// An unmodifiable multi-value map.
  Map<String, List<String>> toMultiValueMap() {
    return Map<String, List<String>>.unmodifiable(
      _values.map((key, value) {
        return MapEntry<String, List<String>>(
          key,
          List<String>.unmodifiable(value),
        );
      }),
    );
  }

  void _fill(HeadersInit init) {
    if (init == null) {
      return;
    }

    switch (init) {
      case final Headers headers:
        for (final entry in headers._values.entries) {
          _values[entry.key] = List<String>.from(entry.value);
        }
      case final Map<String, String> map:
        for (final entry in map.entries) {
          set(entry.key, entry.value);
        }
      case final Map<String, Object?> map:
        for (final entry in map.entries) {
          final value = entry.value;
          if (value == null) {
            continue;
          }
          if (value is Iterable && value is! String) {
            for (final item in value) {
              append(entry.key, item);
            }
          } else {
            set(entry.key, value);
          }
        }
      case final Iterable<MapEntry<String, String>> entries:
        for (final entry in entries) {
          append(entry.key, entry.value);
        }
      case final Iterable<(String, String)> entries:
        for (final entry in entries) {
          append(entry.$1, entry.$2);
        }
      default:
        throw ArgumentError.value(init, 'init', 'Unsupported headers input.');
    }
  }

  static String _normalizeName(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Header name cannot be empty.');
    }
    return normalized;
  }
}
