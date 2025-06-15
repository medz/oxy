extension on String {
  String tryDecodeQueryComponent() {
    try {
      return Uri.decodeQueryComponent(this);
    } catch (_) {
      return this;
    }
  }

  String tryEncodeQueryComponent() {
    try {
      return Uri.encodeQueryComponent(this);
    } catch (_) {
      return this;
    }
  }

  String cleanStartWithQuestionMark() {
    String result = this;
    while (result.startsWith('?')) {
      result = result.substring(1);
    }

    return result;
  }
}

extension type URLSearchParams._(List<(String, String)> _) {
  factory URLSearchParams() => URLSearchParams._([]);

  factory URLSearchParams.parse(String query) {
    final parts = query.cleanStartWithQuestionMark().split("&").map((e) {
      final [name, ...values] = e.split('=');
      if (values.isEmpty) return (name.tryDecodeQueryComponent(), '');

      final value = values.join("").tryDecodeQueryComponent();
      return (name.tryDecodeQueryComponent(), value);
    });

    return URLSearchParams._(List.from(parts));
  }

  factory URLSearchParams.fromMap(Map<String, String> source) {
    final parts = source.entries.map(
      (e) =>
          (e.key.tryDecodeQueryComponent(), e.value.tryDecodeQueryComponent()),
    );

    return URLSearchParams._(List.from(parts));
  }

  int get size => _.length;
  Iterable<String> keys() => _.map((e) => e.$1);
  Iterable<String> values() => _.map((e) => e.$2);

  void append(String name, String value) => _.add((name, value));

  void delete(String name, [String? value]) {
    _.removeWhere((e) {
      final nameEq = e.$1 == name;
      if (nameEq && value != null) return e.$2 == value;
      return nameEq;
    });
  }

  Iterable<List<String>> entries() sync* {
    for (final (name, value) in _) {
      yield [name, value];
    }
  }

  String? get(String name) {
    for (final (key, value) in _) {
      if (key == name) return value;
    }

    return null;
  }

  Iterable<String> getAll(String name) sync* {
    for (final (key, value) in _) {
      if (key == name) yield value;
    }
  }

  bool has(String name, [String? value]) {
    for (final (k, v) in _) {
      final nameEq = k == name;
      if (nameEq && value != null) return value == v;
      return nameEq;
    }

    return false;
  }

  void set(String name, String value) {
    _
      ..removeWhere((e) => e.$1 == name)
      ..add((name, value));
  }

  void sort() {
    _.sort((a, b) => a.$1.compareTo(b.$1));
  }

  String stringify() {
    if (size == 0) return "";
    return _
        .map((e) {
          return '${e.$1.tryEncodeQueryComponent()}=${e.$2.tryEncodeQueryComponent()}';
        })
        .join('&');
  }
}
