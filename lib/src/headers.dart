import '_internal/entry_store.dart';

class Headers extends EntryStore<String> {
  Headers([Map<String, String>? init]) : super(caseSensitive: false) {
    if (init != null && init.isNotEmpty) {
      for (final MapEntry(:key, :value) in init.entries) {
        append(key, value);
      }
    }
  }

  @override
  String? get(String name) {
    final normalized = name.toLowerCase();
    if ('set-cookie' == normalized) {
      return null;
    }

    return super.get(name);
  }

  @override
  Iterable<String> getAll(String name) {
    final normalized = name.toLowerCase();
    if ('set-cookie' == normalized) {
      return [];
    }

    return super.getAll(name);
  }

  Iterable<String> getSetCookie() => super.getAll('set-cookie');
}
