import 'dart:async';
import 'dart:typed_data';

import '../core/body.dart';
import '../core/errors.dart';
import '../core/headers.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';
import '../policies.dart';

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

    final requestControl = _parseCacheControl(request.headers);
    if (requestControl.noStore) {
      return next(request, context);
    }

    final key = keyBuilder(request, context);
    final cached = await _store.read(key);
    final now = DateTime.now().toUtc();
    if (cached != null &&
        cached.isFresh(now) &&
        !requestControl.requiresRevalidation &&
        !_hasConditionalHeader(request.headers)) {
      return _cloneCached(cached.response);
    }

    final revalidationRequest = _revalidationRequest(request, cached);
    final response = await next(
      revalidationRequest,
      cached == null ? context : _allowNotModified(context),
    );
    final receivedAt = DateTime.now().toUtc();
    if (response.status == 304 && cached != null) {
      final merged = _mergeNotModified(cached.response, response);
      await _store.write(
        key,
        CachedResponse(
          response: merged,
          storedAt: receivedAt,
          expiresAt: _expiresAt(merged, receivedAt),
          etag: merged.headers.get('etag') ?? cached.etag,
        ),
      );
      return _cloneCached(merged);
    }

    final cacheControl = _parseCacheControl(response.headers);
    if (cacheControl.noStore ||
        _hasVaryStar(response.headers) ||
        !_cacheableStatus(response.status)) {
      await _store.delete(key);
      return response;
    }

    final buffered = await _tryBuffer(request, response);
    if (buffered == null) {
      await _store.delete(key);
      return response;
    }

    final expiresAt = _expiresAt(buffered, receivedAt);
    final etag = buffered.headers.get('etag');
    if (expiresAt != null || etag != null) {
      await _store.write(
        key,
        CachedResponse(
          response: buffered,
          storedAt: receivedAt,
          expiresAt: expiresAt,
          etag: etag,
        ),
      );
    }
    return buffered.copyWith(fromCache: false);
  }

  static String _defaultCacheKeyBuilder(Request request, Context _) {
    final headers = request.headers.keys().toList()..sort();
    final headerParts = <String>[];
    for (final name in headers) {
      if (_cacheKeyIgnoredHeaders.contains(name)) {
        continue;
      }
      headerParts.add('$name=${request.headers.getAll(name).join('\u0000')}');
    }
    return '${request.method.toUpperCase()} ${request.url}\n'
        '${headerParts.join('\n')}';
  }

  Context _allowNotModified(Context context) {
    return context.copyWith(
      statusPolicy: StatusPolicy(
        accept: (response) {
          return response.status == 304 ||
              context.statusPolicy.accepts(response);
        },
      ),
    );
  }

  Request _revalidationRequest(Request request, CachedResponse? cached) {
    final etag = cached?.etag;
    if (etag == null || _hasConditionalHeader(request.headers)) {
      return request;
    }
    return request.withHeader('if-none-match', etag);
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
    if (control.noStore || control.noCache) {
      return null;
    }
    if (control.maxAge != null) {
      final freshSeconds = control.maxAge! - _ageSeconds(response.headers);
      if (freshSeconds <= 0) {
        return now;
      }
      return now.add(Duration(seconds: freshSeconds));
    }
    return null;
  }

  int _ageSeconds(Headers headers) {
    final value = headers.get('age');
    if (value == null) {
      return 0;
    }
    final seconds = int.tryParse(value.trim());
    if (seconds == null || seconds <= 0) {
      return 0;
    }
    return seconds;
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
    var noCache = false;
    int? maxAge;
    for (final part in value.split(',')) {
      final trimmed = part.trim().toLowerCase();
      if (trimmed == 'no-store') {
        noStore = true;
      }
      if (trimmed == 'no-cache') {
        noCache = true;
      }
      if (trimmed.startsWith('max-age=')) {
        maxAge = int.tryParse(trimmed.substring('max-age='.length));
      }
    }
    return _CacheControl(noStore: noStore, noCache: noCache, maxAge: maxAge);
  }

  bool _hasVaryStar(Headers headers) {
    return headers
        .getAll('vary')
        .expand((value) => value.split(','))
        .any((value) => value.trim() == '*');
  }

  Future<Response?> _tryBuffer(Request request, Response response) async {
    final body = response.body;
    if (body == null) {
      return response;
    }

    final contentLength = body.contentLength;
    if (contentLength != null && contentLength > maxEntryBytes) {
      return null;
    }

    final iterator = StreamIterator<Uint8List>(body.open());
    final chunks = <Uint8List>[];
    final builder = BytesBuilder(copy: false);
    try {
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        chunks.add(chunk);
        builder.add(chunk);
        if (builder.length > maxEntryBytes) {
          response.body = ResponseBody.stream(
            _restoreBody(chunks, iterator),
            contentLength: body.contentLength,
          );
          return null;
        }
      }
      return response.copyWith(
        body: ResponseBody.fromBytes(builder.takeBytes()),
      );
    } catch (error, trace) {
      if (error is RequestError) {
        rethrow;
      }
      throw NetworkError(
        error.toString(),
        request: request,
        cause: error,
        trace: trace,
        sent: true,
      );
    }
  }

  Stream<List<int>> _restoreBody(
    List<Uint8List> chunks,
    StreamIterator<Uint8List> iterator,
  ) async* {
    try {
      for (final chunk in chunks) {
        yield chunk;
      }
      while (await iterator.moveNext()) {
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }
}

const Set<String> _cacheKeyIgnoredHeaders = <String>{
  'cache-control',
  'pragma',
  'if-match',
  'if-modified-since',
  'if-none-match',
  'if-unmodified-since',
  'x-request-id',
};

bool _hasConditionalHeader(Headers headers) {
  return headers.has('if-match') ||
      headers.has('if-modified-since') ||
      headers.has('if-none-match') ||
      headers.has('if-unmodified-since');
}

final class _CacheControl {
  const _CacheControl({
    this.noStore = false,
    this.noCache = false,
    this.maxAge,
  });

  final bool noStore;
  final bool noCache;
  final int? maxAge;

  bool get requiresRevalidation => noCache || maxAge == 0;
}
