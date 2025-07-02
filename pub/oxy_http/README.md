# Oxy HTTP

A simple HTTP adapter for [Oxy](https://pub.dev/packages/oxy) that uses Dart's `http` package as the underlying HTTP implementation.

[![Pub Version](https://img.shields.io/pub/v/oxy_http)](https://pub.dev/packages/oxy_http)
[![Dart Version](https://img.shields.io/badge/Dart-%5E3.8.1-blue)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This adapter bridges Oxy with the popular `http` package, providing a battle-tested HTTP implementation for those who prefer using the `http` package's underlying transport layer.

## Installation

Add `oxy_http` to your `pubspec.yaml`:

```yaml
dependencies:
  oxy: ^0.0.3
  oxy_http: ^0.0.1
```

## Usage

Simply pass the `OxyHttp` adapter to your Oxy client:

```dart
import 'package:oxy/oxy.dart';
import 'package:oxy_http/oxy_http.dart';

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

- You want to use the `http` package's HTTP implementation
- You need compatibility with existing `http` package configurations
- You prefer the `http` package's behavior over the default adapter

## Features

- Full compatibility with all Oxy features
- Uses the reliable `http` package underneath
- Works on all Dart platforms
- Drop-in replacement for the default adapter

## License

MIT License - see the [LICENSE](../../LICENSE) file for details.