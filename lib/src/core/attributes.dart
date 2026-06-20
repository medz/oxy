/// A typed key for values stored in [Attributes].
final class AttributeKey<T extends Object> {
  const AttributeKey(this.name);

  /// A human-readable key name for debugging.
  final String name;

  @override
  String toString() => 'AttributeKey<$T>($name)';
}

/// Immutable, typed metadata shared across request processing.
///
/// Attributes let middleware and transports exchange out-of-band data without
/// adding public fields to `Request` or `Context`.
final class Attributes {
  const Attributes([Map<AttributeKey<Object>, Object>? values])
    : _values = values ?? const <AttributeKey<Object>, Object>{};

  final Map<AttributeKey<Object>, Object> _values;

  /// Whether no attributes are stored.
  bool get isEmpty => _values.isEmpty;

  /// Whether at least one attribute is stored.
  bool get isNotEmpty => _values.isNotEmpty;

  /// The value for [key], or `null` when absent or of a different type.
  T? get<T extends Object>(AttributeKey<T> key) {
    final value = _values[key as AttributeKey<Object>];
    return value is T ? value : null;
  }

  /// Whether [key] is present.
  bool contains<T extends Object>(AttributeKey<T> key) {
    return _values.containsKey(key as AttributeKey<Object>);
  }

  /// Returns a copy with [key] set to [value].
  Attributes set<T extends Object>(AttributeKey<T> key, T value) {
    return Attributes(<AttributeKey<Object>, Object>{
      ..._values,
      key as AttributeKey<Object>: value,
    });
  }

  /// Returns a copy without [key].
  Attributes remove<T extends Object>(AttributeKey<T> key) {
    final next = <AttributeKey<Object>, Object>{..._values};
    next.remove(key as AttributeKey<Object>);
    return Attributes(next);
  }

  /// An unmodifiable map view of the stored attributes.
  Map<AttributeKey<Object>, Object> toMap() {
    return Map<AttributeKey<Object>, Object>.unmodifiable(_values);
  }
}
