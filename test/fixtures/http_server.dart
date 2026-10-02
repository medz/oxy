import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final release = Completer<void>();
  server.listen((request) async {
    try {
      request.response.headers
        ..set('access-control-allow-origin', '*')
        ..set('access-control-allow-headers', 'content-type')
        ..set('access-control-allow-methods', 'GET, POST, OPTIONS');
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 204;
      } else if (request.uri.path == '/bytes') {
        request.response.add(List<int>.generate(128 * 1024, (i) => i % 251));
      } else if (request.uri.path == '/stream') {
        request.response.bufferOutput = false;
        request.response.add(utf8.encode('first'));
        await request.response.flush();
        await release.future;
      } else {
        final body = await utf8.decodeStream(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'method': request.method,
            'body': body,
            'path': request.uri.path,
          }),
        );
      }
      await request.response.close();
    } on SocketException {
      // Expected when a test aborts a response or closes the fixture.
    } on HttpException {
      // Expected when a test aborts a response or closes the fixture.
    }
  });
  channel.sink.add('http://127.0.0.1:${server.port}');
  await channel.stream.first;
  release.complete();
  await server.close(force: true);
}
