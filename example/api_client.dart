import 'package:oxy/oxy.dart';
import 'package:oxy/testing.dart';

final class UsersApi {
  UsersApi(this._client);

  final Client _client;

  Future<User> getUser(String id) {
    return _client.decode<User>('GET', '/users/$id', decoder: User.fromJson);
  }
}

final class User {
  const User({required this.id, required this.name});

  final String id;
  final String name;

  static User fromJson(Object? value) {
    final json = value as Map<String, Object?>;
    return User(id: json['id'] as String, name: json['name'] as String);
  }
}

Future<void> main() async {
  final client = Client(
    ClientOptions(
      baseUrl: Uri.parse('https://api.example.com'),
      timeoutPolicy: const TimeoutPolicy(total: Duration(seconds: 10)),
      retryPolicy: const RetryPolicy(maxRetries: 2),
      transport: MockTransport((request, context) async {
        return Response.json({'id': '42', 'name': 'Ada'});
      }),
    ),
  );

  try {
    final users = UsersApi(client);
    final user = await users.getUser('42');
    print(user.name);
  } finally {
    await client.close();
  }
}
