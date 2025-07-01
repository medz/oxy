class _Entry<T> {
  _Entry(this.name, this.normalizedName, this.value);

  final String normalizedName;
  final String name;
  final T value;
}

/// A generic store for managing key-value entries with optional case sensitivity.
///
/// This abstract class provides a base implementation for storing and managing
/// entries where each entry consists of a name (key) and a value. The store
/// supports both case-sensitive and case-insensitive key matching.
///
/// Type parameter [T] represents the type of values stored in the entries.
abstract class EntryStore<T> {
  /// Creates a new entry store.
  ///
  /// If [caseSensitive] is `true`, entry names will be matched case-sensitively.
  /// If `false` (default), entry names will be matched case-insensitively.
  EntryStore({bool caseSensitive = false}) : _caseSensitive = caseSensitive;

  final bool _caseSensitive;
  final _entries = <_Entry<T>>[];

  String _normalizedName(String name) {
    if (_caseSensitive) return name;
    return name.toLowerCase();
  }

  /// Adds a new entry with the given [name] and [value].
  ///
  /// Unlike [set], this method does not remove existing entries with the same
  /// name, allowing multiple entries with the same name to coexist.
  void append(String name, T value) {
    _entries.add(_Entry(_normalizedName(name), name, value));
  }

  /// Removes all entries with the specified [name].
  ///
  /// The comparison is performed according to the case sensitivity setting
  /// of this store. If no entries with the given name exist, this method
  /// has no effect.
  void delete(String name) {
    final normalized = _normalizedName(name);
    _entries.removeWhere((entry) => entry.normalizedName == normalized);
  }

  /// Returns the value of the first entry with the specified [name].
  ///
  /// If no entry with the given name exists, returns `null`.
  /// If multiple entries with the same name exist, returns the value
  /// of the first one found.
  T? get(String name) {
    final normalized = _normalizedName(name);
    for (final entry in _entries) {
      if (entry.normalizedName == normalized) return entry.value;
    }

    return null;
  }

  /// Returns all values associated with the specified [name].
  ///
  /// Returns an [Iterable] containing the values of all entries that
  /// match the given name. If no entries match, returns an empty iterable.
  Iterable<T> getAll(String name) {
    final normalized = _normalizedName(name);
    return _entries
        .where((entry) => entry.normalizedName == normalized)
        .map((entry) => entry.value);
  }

  /// Returns `true` if the store contains at least one entry with the specified [name].
  ///
  /// The comparison is performed according to the case sensitivity setting
  /// of this store.
  bool has(String name) {
    final normalized = _normalizedName(name);
    return _entries.any((entry) => entry.normalizedName == normalized);
  }

  /// Sets the value for the specified [name], replacing any existing entries.
  ///
  /// This method first removes all existing entries with the given name,
  /// then adds a new entry with the specified name and value.
  /// Unlike [append], this ensures only one entry exists for the given name.
  void set(String name, T value) {
    final normalized = _normalizedName(name);
    _entries.removeWhere((entry) => entry.normalizedName == normalized);
    _entries.add(_Entry(normalized, name, value));
  }

  /// Returns an [Iterable] of all entries as name-value pairs.
  ///
  /// Each entry is represented as a record `(String, T)` where the first
  /// element is the entry name and the second element is the entry value.
  Iterable<(String, T)> entries() {
    return _entries.map((entry) => (entry.name, entry.value));
  }

  /// Returns an [Iterable] of all entry names in the store.
  ///
  /// The returned names preserve their original casing as they were
  /// added to the store.
  Iterable<String> keys() {
    return _entries.map((entry) => entry.name);
  }

  /// Returns an [Iterable] of all values in the store.
  ///
  /// The order of values corresponds to the order in which entries
  /// were added to the store.
  Iterable<T> values() {
    return _entries.map((entry) => entry.value);
  }
}
