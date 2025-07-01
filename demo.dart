main() {
  final stream = Stream.fromIterable([1, 2, 3]);
  final subscription = stream.listen((event) {
    print(event);
  });

  subscription.onData((data) {
    print('Received data: $data');
  });
}
