import 'dart:convert';
import 'dart:typed_data';

final smallBytes = Uint8List.fromList(
  List<int>.generate(1024, (index) => index & 0xff, growable: false),
);

final largeBytes = Uint8List.fromList(
  List<int>.generate(64 * 1024, (index) => index & 0xff, growable: false),
);

final jsonPayload = <String, Object?>{
  'id': 42,
  'name': 'Oxy',
  'tags': <String>['http', 'middleware', 'body'],
  'active': true,
};

final jsonText = jsonEncode(jsonPayload);

final headerPairs8 = headerPairs(8);
final headerPairs32 = headerPairs(32);

List<MapEntry<String, String>> headerPairs(int count) {
  return List<MapEntry<String, String>>.generate(
    count,
    (index) => MapEntry('x-oxy-$index', 'value-$index'),
    growable: false,
  );
}
