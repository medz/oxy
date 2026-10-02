import 'package:oxy/oxy.dart';
import 'package:test/test.dart';

final class CountingTransport implements Transport {
  int closeCalls = 0;
  @override
  PlatformCapability get capability => PlatformCapability.test;
  @override
  Future<Response> send(Request request, Context context) async =>
      Response.text('ok');
  @override
  Future<void> close() async {
    closeCalls++;
  }
}

void main() {
  test(
    'closing clients leaves their shared custom transport caller-owned',
    () async {
      final transport = CountingTransport();
      final first = Client(ClientOptions(transport: transport));
      final second = first.withMiddleware(const []);
      await first.close();
      await first.close();
      expect(await (await second.get('https://example.com')).text(), 'ok');
      await second.close();
      expect(transport.closeCalls, 0);
      await expectLater(
        first.get('https://example.com'),
        throwsA(isA<NetworkError>()),
      );
      await transport.close();
      expect(transport.closeCalls, 1);
    },
  );
}
