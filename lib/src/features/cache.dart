import '../core/headers.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';

typedef CacheKeyBuilder = String Function(Request request, Context context);

final class CachedResponse {
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
    return expiresAt != null && nowUtc.isBefore(expiresAt!);
  }
}

abstract interface class CacheStore {
  Future<CachedResponse?> read(String key);
  Future<void> write(String key, CachedResponse value);
  Future<void> delete(String key);
  Future<void> clear();
}

final class MemoryCacheStore implements CacheStore {
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
    _entries[key] = value;
    return value;
  }

  @override
  Future<void> write(String key, CachedResponse value) async {
    _entries.remove(key);
    _entries[key] = value;
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

final class CacheMiddleware implements Middleware {
  CacheMiddleware({
    CacheStore? store,
    this.keyBuilder = _defaultCacheKeyBuilder,
    this.maxEntryBytes = 1024 * 1024,
    Set<String> methods = const <String>{'GET', 'HEAD'},
  }) : _store = store ?? MemoryCacheStore(),
       _methods = methods.map((method) => method.toUpperCase()).toSet();

  final CacheStore _store;
  final CacheKeyBuilder keyBuilder;
  final int maxEntryBytes;
  final Set<String> _methods;

  @override
  Future<Response> intercept(
    Request request,
    Context context,
    Next next,
  ) async {
    if (!_methods.contains(request.method.toUpperCase())) {
      return next(request, context);
    }

    final key = keyBuilder(request, context);
    final cached = await _store.read(key);
    final now = DateTime.now().toUtc();
    if (cached != null && cached.isFresh(now)) {
      return _cloneCached(cached.response);
    }

    final revalidationRequest = cached?.etag == null
        ? request
        : request.withHeader('if-none-match', cached!.etag!);
    final response = await next(revalidationRequest, context);
    if (response.status == 304 && cached != null) {
      final merged = _mergeNotModified(cached.response, response);
      await _store.write(
        key,
        CachedResponse(
          response: merged,
          storedAt: now,
          expiresAt: _expiresAt(merged, now),
          etag: merged.headers.get('etag') ?? cached.etag,
        ),
      );
      return _cloneCached(merged);
    }

    final cacheControl = _parseCacheControl(response.headers);
    if (cacheControl.noStore || !_cacheableStatus(response.status)) {
      await _store.delete(key);
      return response;
    }

    final buffered = await response.buffered(maxBytes: maxEntryBytes);
    final expiresAt = _expiresAt(buffered, now);
    final etag = buffered.headers.get('etag');
    if (expiresAt != null || etag != null) {
      await _store.write(
        key,
        CachedResponse(
          response: buffered,
          storedAt: now,
          expiresAt: expiresAt,
          etag: etag,
        ),
      );
    }
    return _cloneCached(buffered);
  }

  static String _defaultCacheKeyBuilder(Request request, Context _) {
    return '${request.method.toUpperCase()} ${request.url}';
  }

  Response _cloneCached(Response response) {
    return Response(
      response.body,
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
      url: response.url,
      redirected: response.redirected,
      fromCache: true,
    );
  }

  Response _mergeNotModified(Response cached, Response notModified) {
    final headers = Headers(cached.headers);
    for (final name in notModified.headers.keys()) {
      if (name == 'content-length' || name == 'content-type') {
        continue;
      }
      headers.delete(name);
      for (final value in notModified.headers.getAll(name)) {
        headers.append(name, value);
      }
    }
    return Response(
      cached.body,
      status: cached.status,
      statusText: cached.statusText,
      headers: headers,
      url: cached.url,
      redirected: cached.redirected,
      fromCache: true,
    );
  }

  DateTime? _expiresAt(Response response, DateTime now) {
    final control = _parseCacheControl(response.headers);
    if (control.noStore) {
      return null;
    }
    if (control.maxAge != null) {
      return now.add(Duration(seconds: control.maxAge!));
    }
    return null;
  }

  bool _cacheableStatus(int status) {
    return const <int>{200, 203, 204, 206, 300, 301, 308}.contains(status);
  }

  _CacheControl _parseCacheControl(Headers headers) {
    final value = headers.get('cache-control');
    if (value == null) {
      return const _CacheControl();
    }

    var noStore = false;
    int? maxAge;
    for (final part in value.split(',')) {
      final trimmed = part.trim().toLowerCase();
      if (trimmed == 'no-store') {
        noStore = true;
      }
      if (trimmed.startsWith('max-age=')) {
        maxAge = int.tryParse(trimmed.substring('max-age='.length));
      }
    }
    return _CacheControl(noStore: noStore, maxAge: maxAge);
  }
}

final class _CacheControl {
  const _CacheControl({this.noStore = false, this.maxAge});

  final bool noStore;
  final int? maxAge;
}
