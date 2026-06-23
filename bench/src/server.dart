import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'data.dart';

BenchmarkServer? _activeServer;
final _jsonContentLength = utf8.encode(jsonText).length;

BenchmarkServer get benchmarkServer {
  final server = _activeServer;
  if (server == null) {
    throw StateError('Benchmark server has not been started.');
  }
  return server;
}

Future<BenchmarkServer> startBenchmarkServer() async {
  final active = _activeServer;
  if (active != null) {
    return active;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final benchmarkServer = BenchmarkServer._(server);
  _activeServer = benchmarkServer;
  unawaited(server.forEach(benchmarkServer._handleRequest));
  return benchmarkServer;
}

Future<void> closeBenchmarkServer() async {
  final server = _activeServer;
  _activeServer = null;
  await server?._server.close(force: true);
}

final class BenchmarkServer {
  BenchmarkServer._(this._server)
    : baseUri = Uri.parse('http://${_server.address.host}:${_server.port}');

  final HttpServer _server;
  final Uri baseUri;

  Uri uri(String path) => baseUri.replace(path: path);

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      switch ((request.method, request.uri.path)) {
        case ('GET', '/empty'):
          request.response.contentLength = 0;
        case ('GET', '/json'):
          _writeJson(request.response);
        case ('GET', '/bytes-64k'):
          _writeBytes(request.response);
        case ('POST', '/json'):
          final bytes = await _drainRequest(request);
          if (bytes == _jsonContentLength) {
            request.response.headers.set('x-request-bytes', bytes.toString());
            _writeJson(request.response);
          } else {
            _writeBadRequest(request.response);
          }
        case ('POST', '/bytes-64k'):
          final bytes = await _drainRequest(request);
          if (bytes == largeBytes.length) {
            request.response.headers.set('x-request-bytes', bytes.toString());
            request.response.contentLength = 0;
          } else {
            _writeBadRequest(request.response);
          }
        default:
          await _drainRequest(request);
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('missing');
      }
    } finally {
      await request.response.close();
    }
  }

  void _writeJson(HttpResponse response) {
    response.headers.contentType = ContentType.json;
    response.contentLength = _jsonContentLength;
    response.write(jsonText);
  }

  void _writeBytes(HttpResponse response) {
    response.headers.contentType = ContentType.binary;
    response.contentLength = largeBytes.length;
    response.add(largeBytes);
  }

  void _writeBadRequest(HttpResponse response) {
    response
      ..statusCode = HttpStatus.badRequest
      ..write('unexpected request body');
  }

  Future<int> _drainRequest(HttpRequest request) async {
    var bytes = 0;
    await for (final chunk in request) {
      bytes += chunk.length;
    }
    return bytes;
  }
}
