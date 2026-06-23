import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;

import 'src/data.dart';
import 'src/runner.dart';

final dioSuite = BenchmarkSuite('dio', <BenchmarkCase>[
  SyncBenchmark(
    group: 'request',
    name: 'construct-options',
    run: () {
      consume(
        dio.RequestOptions(
          path: _uri.toString(),
          method: 'GET',
          headers: Map<String, String>.from(_headers8),
        ),
      );
    },
  ),
  SyncBenchmark(
    group: 'request',
    name: 'construct-post-json-options',
    run: () {
      consume(
        dio.RequestOptions(
          path: _uri.toString(),
          method: 'POST',
          headers: Map<String, String>.from(_jsonHeaders),
          data: jsonPayload,
        ),
      );
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'send-no-interceptors',
    run: () async {
      consume(await _client.getUri<Object?>(_uri, options: _headersOptions));
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'post-json-body',
    run: () async {
      consume(await _client.postUri<Object?>(_uri, data: jsonPayload));
    },
  ),
  AsyncBenchmark(
    group: 'client',
    name: 'send-5-interceptors',
    run: () async {
      consume(
        await _interceptorClient.getUri<Object?>(
          _uri,
          options: _headersOptions,
        ),
      );
    },
  ),
  AsyncBenchmark(
    group: 'response',
    name: 'bytes-1k',
    run: () async {
      consume(
        await _client.getUri<List<int>>(_bytesUri, options: _bytesOptions),
      );
    },
  ),
  AsyncBenchmark(
    group: 'response',
    name: 'json-decode',
    run: () async {
      consume(await _client.getUri<Map<String, Object?>>(_jsonUri));
    },
  ),
]);

final _uri = Uri.parse('https://example.test/users/42');
final _jsonUri = Uri.parse('https://example.test/json');
final _bytesUri = Uri.parse('https://example.test/bytes');
final _headers8 = Map<String, String>.fromEntries(headerPairs8);
const _jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};
final _headersOptions = dio.Options(headers: _headers8);
final _bytesOptions = dio.Options(responseType: dio.ResponseType.bytes);

final _client = _createClient();
final _interceptorClient = _createClient()
  ..interceptors.addAll(
    List<dio.Interceptor>.filled(5, const _NoopInterceptor()),
  );

dio.Dio _createClient() {
  return dio.Dio(
    dio.BaseOptions(
      responseType: dio.ResponseType.json,
      validateStatus: (_) => true,
    ),
  )..httpClientAdapter = const _StaticDioAdapter();
}

final class _StaticDioAdapter implements dio.HttpClientAdapter {
  const _StaticDioAdapter();

  @override
  Future<dio.ResponseBody> fetch(
    dio.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    if (options.uri == _jsonUri) {
      return dio.ResponseBody.fromString(
        jsonText,
        200,
        headers: const <String, List<String>>{
          'content-type': <String>['application/json; charset=utf-8'],
        },
      );
    }
    if (options.uri == _bytesUri) {
      return dio.ResponseBody.fromBytes(
        smallBytes,
        200,
        headers: <String, List<String>>{
          'content-length': <String>[smallBytes.length.toString()],
        },
      );
    }
    return dio.ResponseBody.fromBytes(const <int>[], 200);
  }

  @override
  void close({bool force = false}) {}
}

final class _NoopInterceptor extends dio.Interceptor {
  const _NoopInterceptor();

  @override
  void onRequest(
    dio.RequestOptions options,
    dio.RequestInterceptorHandler handler,
  ) {
    handler.next(options);
  }

  @override
  void onResponse(
    dio.Response<dynamic> response,
    dio.ResponseInterceptorHandler handler,
  ) {
    handler.next(response);
  }
}
