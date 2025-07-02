import 'dart:typed_data';

/// An interface that provides helper methods for extracting data in different formats.
///
/// This interface can be implemented by any class that contains or manages data,
/// providing convenient methods for consuming that data as bytes, text, or JSON.
/// Common implementations include HTTP responses, file readers, or any data container
/// that needs to expose its content in multiple formats.
///
/// All methods are asynchronous and return [Future]s, allowing for efficient
/// handling of potentially large data without blocking the main thread.
abstract interface class DataHelpers {
  /// Extracts the data as raw bytes.
  ///
  /// Returns a [Future] that completes with a [Uint8List] containing the raw
  /// binary data. This is useful for handling binary content such as images,
  /// files, or any non-text data.
  ///
  /// Example:
  /// ```dart
  /// final bytes = await dataSource.bytes();
  /// // Write bytes to a file or process binary data
  /// ```
  ///
  /// Throws an exception if the data cannot be read or if there's an error
  /// during the data extraction process.
  Future<Uint8List> bytes();

  /// Extracts the data as a text string.
  ///
  /// Returns a [Future] that completes with a [String] containing the data
  /// decoded as text. The encoding is typically UTF-8, but may vary depending
  /// on the implementation and available metadata.
  ///
  /// Example:
  /// ```dart
  /// final text = await dataSource.text();
  /// print('Response: $text');
  /// ```
  ///
  /// Throws an exception if the data cannot be read, decoded, or if there's
  /// an error during the text extraction process.
  Future<String> text();

  /// Extracts the data as a parsed JSON object.
  ///
  /// Returns a [Future] that completes with the parsed JSON data. The return
  /// type is [Object?] as JSON can represent various types including:
  /// - [Map<String, dynamic>] for JSON objects
  /// - [List<dynamic>] for JSON arrays
  /// - [String], [num], [bool], or [null] for JSON primitives
  ///
  /// The data is first decoded as text and then parsed using Dart's built-in
  /// JSON decoder.
  ///
  /// Example:
  /// ```dart
  /// final data = await dataSource.json();
  /// if (data is Map<String, dynamic>) {
  ///   print('User name: ${data['name']}');
  /// }
  /// ```
  ///
  /// Throws a [FormatException] if the data is not valid JSON.
  /// Throws an exception if the data cannot be read or if there's an error
  /// during the JSON parsing process.
  Future<Object?> json();
}
