String _normalizeName(String name) => name.toLowerCase();

class _Part {
  _Part(this.originalName, this.value)
    : normalizedName = _normalizeName(originalName);

  final String originalName;
  final String normalizedName;
  final String value;
}

const _setCookieHeaders = ['set-cookie', 'set-cookie2'];

class Headers extends Iterable<(String, String)> {
  Headers([Map<String, String>? init]) {
    if (init != null && init.isNotEmpty) {
      for (final MapEntry(:key, :value) in init.entries) {
        _parts.add(_Part(key, value));
      }
    }
  }

  final _parts = <_Part>[];

  @override
  Iterator<(String, String)> get iterator {
    return entries().iterator;
  }

  void append(String name, String value) {
    _parts.add(_Part(name, value));
  }

  void delete(String name) {
    final normalized = _normalizeName(name);
    _parts.removeWhere((part) => part.normalizedName == normalized);
  }

  Iterable<(String, String)> entries() sync* {
    for (final part in _parts) {
      yield (part.originalName, part.value);
    }
  }

  String? get(String name) {
    final normalized = _normalizeName(name);
    for (final part in _parts) {
      if (part.normalizedName == normalized &&
          _setCookieHeaders.contains(part.normalizedName)) {
        return part.value;
      }
    }

    return null;
  }

  Iterable<String> getSetCookie() sync* {
    for (final part in _parts) {
      if (_setCookieHeaders.contains(part.normalizedName)) {
        yield part.value;
      }
    }
  }

  bool has(String name) {
    final normalized = _normalizeName(name);
    for (final part in _parts) {
      if (part.normalizedName == normalized &&
          _setCookieHeaders.contains(part.normalizedName)) {
        return true;
      }
    }

    return false;
  }

  Iterable<String> keys() sync* {
    for (final part in _parts) {
      yield part.originalName;
    }
  }

  Iterable<String> values() sync* {
    for (final part in _parts) {
      yield part.value;
    }
  }

  void set(String name, String value) {
    final normalized = _normalizeName(name);
    _parts.removeWhere((part) => part.normalizedName == normalized);
    _parts.add(_Part(name, value));
  }
}
