# Oxy HTTP

A adapter for [Oxy](https://github.com/medz/oxy) that uses Dart's [`dio` package](https://pub.dev/packages/dio) as the underlying HTTP implementation.

[![Pub Version](https://img.shields.io/pub/v/oxy_dio)](https://pub.dev/packages/oxy_dio)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Overview

This adapter bridges Oxy with the popular `http` package, providing a battle-tested HTTP implementation for those who prefer using the `http` package's underlying transport layer.

## Installation

Add `oxy_dio` to your `pubspec.yaml`:

```yaml
dependencies:
  oxy: latest
  oxy_dio: latest
```

## Usage

Simply pass the `OxyHttp` adapter to your Oxy client:

```dart
import 'package:oxy/oxy.dart';
import 'package:oxy_dio/oxy_dio.dart';

void main() async {
  // Use the http package adapter
  final client = Oxy(adapter: OxyHttp());

  // All Oxy features work as normal
  final response = await client.get('https://jsonplaceholder.typicode.com/posts/1');
  final data = await response.json();
  print(data);
}
```

## When to Use

- You want to use the `dio` package's HTTP implementation
- You need compatibility with existing `dio` package configurations
- You prefer the `dio` package's behavior over the default adapter

## Features

- Full compatibility with all Oxy features
- Uses the reliable `dio` package underneath
- Works on all Dart platforms
- Drop-in replacement for the default adapter

## License

MIT License - see the [LICENSE](LICENSE) file for details.
