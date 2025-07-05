import 'package:oxy/oxy.dart' as oxy;
import 'package:dio/dio.dart';

/// A Oxy implementation that uses the Dio HTTP client.
///
/// This adapter bridges the Oxy HTTP interface with the Dio package,
/// allowing Oxy to make HTTP requests using Dio's implementation.
class OxyDio implements oxy.Adapter {
  /// Creates a new [OxyDio] adapter instance.
  ///
  /// The [dio] parameter is optional. If provided, it will be used as the
  /// underlying Dio client. If not provided, a new default [Dio] instance
  /// will be created.
  OxyDio({Dio? dio}) : dio = dio ?? Dio();

  /// The underlying Dio HTTP client used by this adapter.
  final Dio dio;

  @override
  bool get isSupportWeb => true;

  @override
  Future<oxy.Response> fetch(Uri url, oxy.AdapterRequest request) async {
    final requestHeaders = <String, String>{};
    for (final name in request.headers.keys()) {
      final values = request.headers.getAll(name);
      if (values.isNotEmpty) {
        requestHeaders[name] = values.join(', ');
      }
    }

    final options = RequestOptions(
      method: request.method,
      path: url.toString(),
      responseType: ResponseType.stream,
      data: request.body,
      headers: requestHeaders,
      followRedirects: request.redirect == oxy.RequestRedirect.follow,
      maxRedirects: request.redirect == oxy.RequestRedirect.follow ? 5 : 0,
      validateStatus: (_) => true,
    );
    final dioResponse = await dio.fetch<ResponseBody>(options).catchError((e) {
      request.signal.abort(e);
      throw e;
    });
    final body = oxy.Body(dioResponse.data!.stream);
    body.headers.set(
      "content-type",
      dioResponse.headers.value("content-type") ?? "application/octet-stream",
    );
    final headers = oxy.Headers();
    for (final entry in dioResponse.headers.map.entries) {
      for (final value in entry.value) {
        headers.append(entry.key, value);
      }
    }

    final response = oxy.Response(
      status: dioResponse.statusCode ?? 200,
      statusText: dioResponse.statusMessage,
      url: dioResponse.realUri.toString(),
      body: body,
      headers: headers,
      redirected: dioResponse.isRedirect,
    );

    if (request.redirect == oxy.RequestRedirect.error && response.redirected) {
      throw response;
    }

    return response;
  }
}
