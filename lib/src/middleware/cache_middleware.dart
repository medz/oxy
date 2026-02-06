import 'package:ht/ht.dart';

import '../options.dart';

typedef CacheKeyBuilder =
    String Function(Request request, RequestOptions options);

class CacheOptionsKeys {
  static const String bypass = 'cache.bypass';
}

class CachedResponse {
  const CachedResponse({
    required this.response,
    required this.storedAt,
    required this.expiresAt,
    required this.etag,
  });

  final Response response;
  final DateTime storedAt;
  final DateTime? expiresAt;
  final String? etag;

  bool isFresh(DateTime nowUtc) {
    if (expiresAt == null) {
      return false;
    }

    return nowUtc.isBefore(expiresAt!);
  }

  CachedResponse clone() {
    return CachedResponse(
      response: response.clone(),
      storedAt: storedAt,
      expiresAt: expiresAt,
      etag: etag,
    );
  }
}

abstract interface class CacheStore {
  Future<CachedResponse?> read(String key);
  Future<void> write(String key, CachedResponse value);
  Future<void> delete(String key);
  Future<void> clear();
}

class MemoryCacheStore implements CacheStore {
  MemoryCacheStore({this.maxEntries})
    : assert(maxEntries == null || maxEntries > 0, 'maxEntries must be > 0');

  final int? maxEntries;
  final Map<String, CachedResponse> _entries = <String, CachedResponse>{};

  @override
  Future<void> clear() async {
    _entries.clear();
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  @override
  Future<CachedResponse?> read(String key) async {
    final value = _entries.remove(key);
    if (value == null) {
      return null;
    }

    // Move to the newest position to preserve LRU ordering.
    _entries[key] = value;
    return value.clone();
  }

  @override
  Future<void> write(String key, CachedResponse value) async {
    _entries.remove(key);
    _entries[key] = value.clone();
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    final limit = maxEntries;
    if (limit == null) {
      return;
    }

    while (_entries.length > limit) {
      _entries.remove(_entries.keys.first);
    }
  }
}

class CacheMiddleware implements OxyMiddleware {
  CacheMiddleware({
    CacheStore? store,
    this.keyBuilder = _defaultCacheKeyBuilder,
    Set<String> cacheMethods = const <String>{'GET', 'HEAD'},
  }) : _store = store ?? MemoryCacheStore(),
       _cacheMethods = cacheMethods
           .map((method) => method.trim().toUpperCase())
           .toSet();

  final CacheStore _store;
  final CacheKeyBuilder keyBuilder;
  final Set<String> _cacheMethods;

  @override
  Future<Response> intercept(
    Request request,
    RequestOptions options,
    Next next,
  ) async {
    if (!_cacheMethods.contains(request.method.toUpperCase()) ||
        _isBypassed(options)) {
      return next(request, options);
    }

    final key = keyBuilder(request, options);
    final cached = await _store.read(key);
    final now = DateTime.now().toUtc();

    Request nextRequest = request;

    if (cached != null && cached.isFresh(now)) {
      return cached.response.clone();
    }

    if (cached != null && cached.etag != null) {
      nextRequest = _attachIfNoneMatch(request, cached.etag!);
    }

    final response = await next(nextRequest, options);

    if (response.status == 304 && cached != null) {
      final merged = _mergeNotModified(cached.response, response);
      final renewed = _buildCacheEntry(merged, now, fallbackEtag: cached.etag);
      if (renewed != null) {
        await _store.write(key, renewed);
      }
      return merged;
    }

    final cacheControl = _parseCacheControl(
      response.headers.get('cache-control'),
    );
    if (cacheControl.noStore) {
      await _store.delete(key);
      return response;
    }

    final entry = _buildCacheEntry(response, now);
    if (entry != null) {
      await _store.write(key, entry);
    }

    return response;
  }

  static String _defaultCacheKeyBuilder(
    Request request,
    RequestOptions options,
  ) {
    return '${request.method.toUpperCase()} ${request.url}';
  }

  bool _isBypassed(RequestOptions options) {
    return options.extra[CacheOptionsKeys.bypass] == true;
  }

  Request _attachIfNoneMatch(Request request, String etag) {
    if (request.headers.has('if-none-match')) {
      return request;
    }

    final headers = request.headers.clone()..set('if-none-match', etag);
    return request.copyWith(headers: headers);
  }

  Response _mergeNotModified(Response cached, Response notModified) {
    final base = cached.clone();
    final headers = base.headers.clone();
    _overrideHeaders(headers, notModified.headers);

    return base.copyWith(headers: headers);
  }

  CachedResponse? _buildCacheEntry(
    Response response,
    DateTime nowUtc, {
    String? fallbackEtag,
  }) {
    if (!_isCacheableStatus(response.status)) {
      return null;
    }

    final cacheControl = _parseCacheControl(
      response.headers.get('cache-control'),
    );
    if (cacheControl.noStore) {
      return null;
    }

    final etag = response.headers.get('etag') ?? fallbackEtag;
    final expiresAt = _computeExpiresAt(cacheControl, nowUtc, etag: etag);

    if (expiresAt == null && etag == null) {
      return null;
    }

    return CachedResponse(
      response: response.clone(),
      storedAt: nowUtc,
      expiresAt: expiresAt,
      etag: etag,
    );
  }

  bool _isCacheableStatus(int status) {
    return status >= 200 && status < 300;
  }

  DateTime? _computeExpiresAt(
    _ParsedCacheControl cacheControl,
    DateTime nowUtc, {
    required String? etag,
  }) {
    if (cacheControl.noCache) {
      return nowUtc;
    }

    if (cacheControl.maxAge != null) {
      return nowUtc.add(Duration(seconds: cacheControl.maxAge!));
    }

    if (etag != null) {
      return nowUtc;
    }

    return null;
  }

  static void _overrideHeaders(Headers target, Headers source) {
    for (final name in source.names()) {
      target.delete(name);
      for (final value in source.getAll(name)) {
        target.append(name, value);
      }
    }
  }

  _ParsedCacheControl _parseCacheControl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const _ParsedCacheControl();
    }

    var noStore = false;
    var noCache = false;
    int? maxAge;

    final parts = value.split(',');
    for (final raw in parts) {
      final item = raw.trim().toLowerCase();
      if (item.isEmpty) {
        continue;
      }

      if (item == 'no-store') {
        noStore = true;
        continue;
      }

      if (item == 'no-cache') {
        noCache = true;
        continue;
      }

      if (item.startsWith('max-age=')) {
        final seconds = int.tryParse(item.substring('max-age='.length));
        if (seconds != null && seconds >= 0) {
          maxAge = seconds;
        }
      }
    }

    return _ParsedCacheControl(
      noStore: noStore,
      noCache: noCache,
      maxAge: maxAge,
    );
  }
}

class _ParsedCacheControl {
  const _ParsedCacheControl({
    this.noStore = false,
    this.noCache = false,
    this.maxAge,
  });

  final bool noStore;
  final bool noCache;
  final int? maxAge;
}
