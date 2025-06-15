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
  external JSObject _keys();
  Iterable<String> keys() sync* {
    final entries = JSArray.from<JSString>(_keys());
    for (final key in entries.toDart) {
      yield key.toDart;
    }
  }

  @JS("values")
  external JSObject _values();
  Iterable<String> values() sync* {
    final entries = JSArray.from<JSString>(_values());
    for (final value in entries.toDart) {
      yield value.toDart;
    }
  }

  @JS("entries")
  external JSObject _entries();
  Iterable<List<String>> entries() sync* {
    final entries = JSArray.from<JSArray<JSString>>(_entries());
    for (final entry in entries.toDart) {
      final [name, value] = entry.toDart;
      yield [name.toDart, value.toDart];
    }
  }
}
