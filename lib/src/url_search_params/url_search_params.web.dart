import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS("URLSearchParams")
extension type URLSearchParams._(JSObject _) {
  @JS("constructor")
  external factory URLSearchParams._internal([JSAny init]);

  factory URLSearchParams() => URLSearchParams._internal();
  factory URLSearchParams.parse(String query) =>
      URLSearchParams._internal(query.toJS);

  factory URLSearchParams.fromMap(Map<String, String> map) {
    final obj = JSObject();
    for (final entry in map.entries) {
      obj.setProperty(entry.key.toJS, entry.value.toJS);
    }

    return URLSearchParams._internal(obj);
  }

  external int get size;
  external void append(String name, String value);
  external bool has(String name, [String? value]);
  external void delete(String name, [String? value]);
  external void set(String name, String value);
  external void sort();
  external String? get(String name);

  @JS('toString')
  external String stringify();

  @JS("getAll")
  external JSArray<JSString> _getAll(String name);
  Iterable<String> getAll(String name) sync* {
    for (final value in _getAll(name).toDart) {
      yield value.toDart;
    }
  }

  @JS("keys")
  external JSArray<JSString> _keys();
  Iterable<String> keys() sync* {
    for (final key in _keys().toDart) {
      yield key.toDart;
    }
  }

  @JS("values")
  external JSArray<JSString> _values();
  Iterable<String> values() sync* {
    for (final value in _values().toDart) {
      yield value.toDart;
    }
  }

  @JS("entries")
  external JSArray<JSArray<JSString>> _entries();
  Iterable<List<String>> entries() sync* {
    for (final entry in _entries().toDart) {
      final [name, value] = entry.toDart;
      yield [name.toDart, value.toDart];
    }
  }
}
