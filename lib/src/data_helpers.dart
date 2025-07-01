import 'dart:typed_data';

abstract mixin class DataHelpers {
  Future<Uint8List> bytes();
  Future<String> text();
  Future<Object?> json();
}
