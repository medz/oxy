import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS("Headers")
extension type Headers._(JSObject _) implements JSObject {
  factory Headers([Map<String, String>? init]) {
    final obj = JSObject();
    if (init != null && init.isNotEmpty) {
      for (final MapEntry(:key, :value) in init.entries) {
        obj.setProperty(key.toJS, value.toJS);
      }
    }

    return Headers._(obj);
  }

  external void append(String name, String value);
  external void delete(String name);
  external String? get(String name);
  external bool has(String name);
  external void set(String name, String value);

  @JS("entries")
  external JSObject _entries();
  Iterable<List<String>> entries() sync* {
    final entries = JSArray.from<JSArray<JSString>>(_entries());
    for (final entry in entries.toDart) {
      final [name, value] = entry.toDart;
      yield [name.toDart, value.toDart];
    }
  }

  @JS("getSetCookie")
  external JSArray<JSString> _getSetCookie();
  Iterable<String> getSetCookie() sync* {
    for (final item in _getSetCookie().toDart) {
      yield item.toDart;
    }
  }

  @JS("keys")
  external JSObject _keys();
  Iterable<String> keys() sync* {
    final keys = JSArray.from<JSString>(_keys());
    for (final key in keys.toDart) {
      yield key.toDart;
    }
  }

  @JS("values")
  external JSObject _values();
  Iterable<String> values() sync* {
    final values = JSArray.from<JSString>(_values());
    for (final value in values.toDart) {
      yield value.toDart;
    }
  }
}
