class Part {
  Part(this.name, this.values);

  final String name;
  final List<String> values;
}

extension type Headers._(Map<String, Part> _) {
  factory Headers([Map<String, String>? init]) {
    final entries = init?.entries.map(
      (e) => MapEntry(
        e.key.trim().toLowerCase(),
        Part(e.key.trim(), [e.value.trim()]),
      ),
    );
    if (entries == null || entries.isEmpty) {
      return Headers._({});
    }

    return Headers._(Map.fromEntries(entries));
  }

  void append(String name, String value) {
    final normalized = name.trim().toLowerCase();
    _.update(
      normalized,
      (e) => e..values.add(value.trim()),
      ifAbsent: () => Part(name.trim(), [value.trim()]),
    );
  }

  void delete(String name) {
    name = name.toLowerCase().trim();
    _.remove(name);
  }

  String? get(String name) {
    name = name.toLowerCase().trim();
    if (isSetCookie(name)) return null;

    final part = _[name];
    if (part == null) return null;
    return part.values.join(', ');
  }

  Iterable<String> getSetCookie() sync* {
    final setCookie = _['set-cookie'];
    if (setCookie != null) yield* setCookie.values;

    final setCookie2 = _['set-cookie2'];
    if (setCookie2 != null) yield* setCookie2.values;
  }

  bool has(String name) {
    name = name.trim().toLowerCase();
    return _.containsKey(name);
  }

  void set(String name, String value) {
    final normalized = name.toLowerCase().trim();
    _[normalized] = Part(name.trim(), [value]);
  }

  Iterable<String> keys() sync* {
    for (final MapEntry(key: name, value: part) in _.entries) {
      if (isSetCookie(name)) continue;
      yield part.name;
    }
  }

  Iterable<String> values() sync* {
    for (final MapEntry(key: name, value: part) in _.entries) {
      if (isSetCookie(name)) continue;
      yield part.values.join(', ');
    }
  }

  Iterable<List<String>> entries() sync* {
    for (final MapEntry(key: name, value: part) in _.entries) {
      if (isSetCookie(name)) continue;
      yield [part.name, part.values.join(', ')];
    }
  }
}

extension on Headers {
  bool isSetCookie(String name) =>
      name == 'set-cookie' || name == 'set-cookie2';
}
