import 'dart:async';
import 'dart:convert';
import 'dart:io';

// A raw loopback HTTP fixture makes client-side socket closure observable.
// Ordinary responses close their connection; /stream deliberately stays open.
Future<void> main() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final streams = <String, bool>{};
  final sockets = <Socket>{};
  server.listen((socket) {
    sockets.add(socket);
    final pending = <int>[];
    String? streamId;
    var handled = false;

    void disconnected() {
      sockets.remove(socket);
      final id = streamId;
      if (id != null) {
        streams[id] = true;
        stdout.writeln(jsonEncode({'stream': id, 'closed': true}));
      }
      socket.destroy();
    }

    socket.listen(
      (bytes) async {
        if (handled) return;
        pending.addAll(bytes);
        final text = latin1.decode(pending);
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        final lines = text.substring(0, end).split('\r\n');
        final start = lines.first.split(' ');
        final method = start[0];
        final uri = Uri.parse(start[1]);
        final headers = <String, String>{};
        for (final line in lines.skip(1)) {
          final colon = line.indexOf(':');
          if (colon > 0) {
            headers[line.substring(0, colon).toLowerCase()] = line
                .substring(colon + 1)
                .trim();
          }
        }
        final length = int.parse(headers['content-length'] ?? '0');
        if (pending.length < end + 4 + length) return;
        handled = true;
        const cors =
            'Access-Control-Allow-Origin: *\r\n'
            'Access-Control-Allow-Headers: content-type\r\n'
            'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n';
        if (uri.path == '/stream') {
          final id = uri.queryParameters['id']!;
          streamId = id;
          streams[id] = false;
          socket.add(
            ascii.encode(
              'HTTP/1.1 200 OK\r\n$cors'
              'Transfer-Encoding: chunked\r\n\r\n5\r\nfirst\r\n',
            ),
          );
          await socket.flush();
          stdout.writeln(jsonEncode({'stream': id, 'started': true}));
          return;
        }
        final List<int> body;
        if (method == 'OPTIONS') {
          body = const [];
        } else if (uri.path == '/state') {
          final id = uri.queryParameters['id'];
          body = utf8.encode(
            jsonEncode({
              'started': streams.containsKey(id),
              'closed': streams[id] == true,
            }),
          );
        } else if (uri.path == '/bytes') {
          body = List<int>.generate(128 * 1024, (i) => i % 251);
        } else {
          body = utf8.encode(
            jsonEncode({
              'method': method,
              'body': utf8.decode(pending.sublist(end + 4, end + 4 + length)),
            }),
          );
        }
        socket.add(
          ascii.encode(
            'HTTP/1.1 200 OK\r\n$cors'
            'Connection: close\r\nContent-Length: ${body.length}\r\n\r\n',
          ),
        );
        socket.add(body);
        await socket.flush();
        await socket.close();
      },
      onDone: disconnected,
      onError: (Object _) => disconnected(),
    );
  });
  stdout.writeln('BASE_URL=http://127.0.0.1:${server.port}');
  await ProcessSignal.sigterm.watch().first;
  for (final socket in sockets.toList()) {
    socket.destroy();
  }
  await server.close();
}
