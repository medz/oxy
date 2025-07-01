import 'dart:typed_data';

abstract interface class DataHelpers {
  Future<Uint8List> bytes();
  Future<String> text();
  Future<Object?> json();
}
