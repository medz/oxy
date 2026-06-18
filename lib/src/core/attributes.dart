final class AttributeKey<T extends Object> {
  const AttributeKey(this.name);

  final String name;

  @override
  String toString() => 'AttributeKey<$T>($name)';
}

final class Attributes {
  const Attributes([Map<AttributeKey<Object>, Object>? values])
    : _values = values ?? const <AttributeKey<Object>, Object>{};

  final Map<AttributeKey<Object>, Object> _values;

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;

  T? get<T extends Object>(AttributeKey<T> key) {
    final value = _values[key as AttributeKey<Object>];
    return value is T ? value : null;
  }

  bool contains<T extends Object>(AttributeKey<T> key) {
    return _values.containsKey(key as AttributeKey<Object>);
  }

  Attributes set<T extends Object>(AttributeKey<T> key, T value) {
    return Attributes(<AttributeKey<Object>, Object>{
      ..._values,
      key as AttributeKey<Object>: value,
    });
  }

  Attributes remove<T extends Object>(AttributeKey<T> key) {
    final next = <AttributeKey<Object>, Object>{..._values};
    next.remove(key as AttributeKey<Object>);
    return Attributes(next);
  }

  Map<AttributeKey<Object>, Object> toMap() {
    return Map<AttributeKey<Object>, Object>.unmodifiable(_values);
  }
}
