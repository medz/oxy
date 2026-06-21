import 'dart:async';
import 'dart:typed_data';

import '../core/attributes.dart';
import '../core/body.dart';
import '../core/errors.dart';
import '../core/headers.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';

/// Builds a cache key for a request.
typedef CacheKeyBuilder = String Function(Request request, Context context);

const AttributeKey<_CacheState> _cacheStateAttribute = AttributeKey(
  'oxy.cache.state',
);

/// A response stored by [CacheStore].
final class CachedResponse {
  const CachedResponse({
    required this.response,
    required this.storedAt,
    required this.expiresAt,
    required this.etag,
  });

  /// The buffered response.
  final Response response;

  /// When the response was stored.
  final DateTime storedAt;

  /// When the response expires, or `null` if it requires validation.
  final DateTime? expiresAt;

  /// The response ETag used for revalidation.
  final String? etag;

  /// Whether this response is still fresh at [nowUtc].
  bool isFresh(DateTime nowUtc) {
    return expiresAt != null && nowUtc.isBefore(expiresAt!);
  }

  bool _satisfiesRequest(_CacheControl requestControl, DateTime nowUtc) {
    final maxAge = requestControl.maxAge;
    if (maxAge == null) {
      return true;
    }
    final currentAge =
        nowUtc.difference(storedAt) +
        Duration(seconds: _ageSeconds(response.headers));
    return currentAge <= Duration(seconds: maxAge);
  }
}

/// Storage used by [CacheMiddleware].
abstract interface class CacheStore {
  /// Reads the cached response for [key].
  Future<CachedResponse?> read(String key);

  /// Stores [value] for [key].
  Future<void> write(String key, CachedResponse value);

  /// Removes [key].
  Future<void> delete(String key);

  /// Removes all cached entries.
  Future<void> clear();
}

/// In-memory least-recently-used cache store.
final class MemoryCacheStore implements CacheStore {
  MemoryCacheStore({this.maxEntries = defaultMaxEntries})
    : assert(maxEntries == null || maxEntries > 0, 'maxEntries must be > 0');

  /// Default maximum number of entries.
  static const int defaultMaxEntries = 128;

  /// Maximum number of entries, or `null` for no entry limit.
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

/// HTTP cache middleware for cacheable `GET` and `HEAD` responses.
///
/// The middleware stores bounded, replayable responses and revalidates cached
/// entries with ETag or Last-Modified validators when needed.
final class CacheMiddleware
    implements
        RequestTransformer,
        RequestResolver,
        AttemptResponseHandler,
        FinalResponseHandler {
  CacheMiddleware({
    CacheStore? store,
    this.keyBuilder = _defaultCacheKeyBuilder,
    this.maxEntryBytes = 1024 * 1024,
    Set<String> methods = const <String>{'GET', 'HEAD'},
  }) : _store = store ?? MemoryCacheStore(),
       _methods = methods.map((method) => method.toUpperCase()).toSet();

  final CacheStore _store;

  /// Cache key builder.
  final CacheKeyBuilder keyBuilder;

  /// Maximum response body size stored in memory.
  final int maxEntryBytes;
  final Set<String> _methods;

  @override
  Future<Request> onRequest(Request request, Context context) async {
    if (!_methods.contains(request.method.toUpperCase())) {
      return request;
    }

    final requestControl = _parseCacheControl(request.headers);
    if (requestControl.noStore) {
      return request;
    }

    final key = keyBuilder(request, context);
    final cached = await _store.read(key);
    final now = DateTime.now().toUtc();
    final revalidationRequest = _revalidationRequest(request, cached);
    return revalidationRequest.copyWith(
      attributes: revalidationRequest.attributes.set(
        _cacheStateAttribute,
        _CacheState(
          key: key,
          cached: cached,
          canUseFresh:
              cached != null &&
              cached.isFresh(now) &&
              cached._satisfiesRequest(requestControl, now) &&
              !requestControl.requiresRevalidation &&
              !_hasConditionalHeader(request.headers),
        ),
      ),
    );
  }

  @override
  Response? resolve(Request request, Context context) {
    final state = request.attributes.get(_cacheStateAttribute);
    final cached = state?.cached;
    if (state == null || cached == null || !state.canUseFresh) {
      return null;
    }
    return _cloneCached(cached.response);
  }

  @override
  Future<Response> onAttemptResponse(
    Request request,
    Response response,
    Context context,
  ) async {
    final state = request.attributes.get(_cacheStateAttribute);
    final cached = state?.cached;
    if (state == null || cached == null || response.status != 304) {
      return response;
    }

    if (!_notModifiedMatchesCached(request, cached, response)) {
      return response;
    }

    final receivedAt = DateTime.now().toUtc();
    final merged = _mergeNotModified(cached.response, response);
    final mergedControl = _parseCacheControl(merged.headers);
    if (mergedControl.noStore ||
        _hasVaryStar(merged.headers) ||
        !_cacheableStatus(merged.status)) {
      await _store.delete(state.key);
      return _cloneCached(merged);
    }

    await _store.write(
      state.key,
      CachedResponse(
        response: merged,
        storedAt: receivedAt,
        expiresAt: _expiresAt(merged, receivedAt),
        etag: merged.headers.get('etag') ?? cached.etag,
      ),
    );
    return _cloneCached(merged);
  }

  @override
  Future<Response> onResponse(
    Request request,
    Response response,
    Context context,
  ) async {
    final state = request.attributes.get(_cacheStateAttribute);
    if (state == null || response.fromCache || response.status == 304) {
      return response;
    }

    final receivedAt = DateTime.now().toUtc();

    final cacheControl = _parseCacheControl(response.headers);
    if (cacheControl.noStore ||
        _hasVaryStar(response.headers) ||
        !_cacheableStatus(response.status)) {
      await _store.delete(state.key);
      return response;
    }

    final expiresAt = _expiresAt(response, receivedAt);
    final etag = response.headers.get('etag');
    if (expiresAt == null && etag == null) {
      await _store.delete(state.key);
      return response;
    }

    final bufferResult = await _tryBuffer(request, response);
    final cacheResponse = bufferResult.cacheResponse;
    if (cacheResponse == null) {
      await _store.delete(state.key);
      return bufferResult.response;
    }

    await _store.write(
      state.key,
      CachedResponse(
        response: cacheResponse,
        storedAt: receivedAt,
        expiresAt: expiresAt,
        etag: etag,
      ),
    );
    return cacheResponse.copyWith(fromCache: false);
  }

  static String _defaultCacheKeyBuilder(Request request, Context _) {
    final headers = request.headers.keys().toList()..sort();
    final headerParts = <String>[];
    for (final name in headers) {
      if (_cacheKeyIgnoredHeaders.contains(name)) {
        continue;
      }
      headerParts.add(
        '$name=${_headerValues(request.headers, name).join('\u0000')}',
      );
    }
    return '${request.method.toUpperCase()} ${request.url}\n'
        '${headerParts.join('\n')}';
  }

  Request _revalidationRequest(Request request, CachedResponse? cached) {
    if (cached == null || _hasConditionalHeader(request.headers)) {
      return request;
    }

    final etag = cached.etag;
    if (etag != null) {
      return request.copyWith(
        headers: Headers(request.headers)..set('if-none-match', etag),
      );
    }

    final lastModified = cached.response.headers.get('last-modified');
    if (lastModified != null && lastModified.trim().isNotEmpty) {
      return request.copyWith(
        headers: Headers(request.headers)
          ..set('if-modified-since', lastModified),
      );
    }

    return request;
  }

  bool _notModifiedMatchesCached(
    Request request,
    CachedResponse cached,
    Response notModified,
  ) {
    final responseEtag = notModified.headers.get('etag');
    final cachedEtag = cached.etag;
    if (responseEtag != null &&
        cachedEtag != null &&
        !_etagMatches(responseEtag, cachedEtag)) {
      return false;
    }

    if (!_hasConditionalHeader(request.headers)) {
      return cached.etag != null ||
          cached.response.headers.has('last-modified');
    }

    final ifNoneMatch = request.headers.get('if-none-match');
    if (ifNoneMatch != null) {
      if (cachedEtag == null) {
        return false;
      }
      final values = _etagValues(ifNoneMatch).toList();
      final hasWildcard = values.contains('*');
      final requestedEtags = values
          .where((value) => value != '*')
          .map(_weakEtagValue)
          .toSet();
      if (!requestedEtags.contains(_weakEtagValue(cachedEtag))) {
        return false;
      }

      if (responseEtag != null) {
        return _etagMatches(responseEtag, cachedEtag);
      }
      return !hasWildcard && requestedEtags.length == 1;
    }

    final ifModifiedSince = request.headers.get('if-modified-since');
    final lastModified = cached.response.headers.get('last-modified');
    return ifModifiedSince != null &&
        lastModified != null &&
        ifModifiedSince.trim() == lastModified.trim();
  }

  bool _etagMatches(String header, String etag) {
    final normalizedEtag = _weakEtagValue(etag);
    return _etagValues(header)
        .where((value) {
          // A wildcard 304 proves a representation exists, not that it matches
          // the stored response body.
          return value != '*';
        })
        .any((value) => _weakEtagValue(value) == normalizedEtag);
  }

  Iterable<String> _etagValues(String header) {
    return header.split(',').map((value) => value.trim()).where((value) {
      return value.isNotEmpty;
    });
  }

  String _weakEtagValue(String etag) {
    final trimmed = etag.trim();
    return trimmed.startsWith('W/') ? trimmed.substring(2) : trimmed;
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
      for (final value in _headerValues(notModified.headers, name)) {
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

  bool _cacheableStatus(int status) {
    return const <int>{200, 203, 204, 206, 300, 301, 308}.contains(status);
  }

  _CacheControl _parseCacheControl(Headers headers) {
    var noStore = false;
    var noCache = false;
    int? maxAge;

    final cacheControl = headers.get('cache-control');
    if (cacheControl != null) {
      for (final part in cacheControl.split(',')) {
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
    }

    for (final value in _headerValues(headers, 'pragma')) {
      for (final part in value.split(',')) {
        if (part.trim().toLowerCase() == 'no-cache') {
          noCache = true;
        }
      }
    }

    return _CacheControl(noStore: noStore, noCache: noCache, maxAge: maxAge);
  }

  bool _hasVaryStar(Headers headers) {
    return headers
        .entries()
        .where((entry) => entry.key == 'vary')
        .map((entry) => entry.value)
        .expand((value) => value.split(','))
        .any((value) => value.trim() == '*');
  }

  Future<_CacheBufferResult> _tryBuffer(
    Request request,
    Response response,
  ) async {
    final body = response.body;
    if (body == null) {
      return _CacheBufferResult(response: response, cacheResponse: response);
    }

    final contentLength = body.contentLength;
    if (contentLength != null && contentLength > maxEntryBytes) {
      return _CacheBufferResult(response: response);
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
          if (body.replayable) {
            await iterator.cancel();
            return _CacheBufferResult(response: response);
          }
          return _CacheBufferResult(
            response: response.copyWith(
              body: ResponseBody.stream(
                _restoreBody(chunks, iterator),
                contentLength: body.contentLength,
              ),
            ),
          );
        }
      }
      final buffered = response.copyWith(
        body: ResponseBody.fromBytes(builder.takeBytes()),
      );
      return _CacheBufferResult(response: buffered, cacheResponse: buffered);
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

final class _CacheBufferResult {
  const _CacheBufferResult({required this.response, this.cacheResponse});

  final Response response;
  final Response? cacheResponse;
}

final class _CacheState {
  const _CacheState({
    required this.key,
    required this.cached,
    required this.canUseFresh,
  });

  final String key;
  final CachedResponse? cached;
  final bool canUseFresh;
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

Iterable<String> _headerValues(Headers headers, String name) {
  return headers.entries().where((entry) => entry.key == name).map((entry) {
    return entry.value;
  });
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
