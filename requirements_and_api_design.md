# Oxy - Dart Web Standards HTTP 请求库 需求和 API 设计

## 项目概述

Oxy 是一个 Dart HTTP 请求库，旨在提供完全符合 Web Standards 的 Fetch API 实现。项目目标是让开发者能够在 Dart 环境中使用与浏览器中完全一致的 API 进行 HTTP 请求。

### 核心理念

- **Web Standards 兼容性**: 完全遵循 W3C 和 WHATWG 标准
- **跨平台一致性**: 在 Dart Native 和 Web 平台提供相同的 API
- **零学习成本**: 对于熟悉浏览器 Fetch API 的开发者
- **类型安全**: 充分利用 Dart 的类型系统

## 功能需求

### 1. 核心 Web APIs

#### 1.1 Fetch API
- [x] 基础 fetch() 函数
- [ ] RequestInit 配置对象
- [ ] AbortController 支持
- [ ] 流式响应处理
- [ ] CORS 支持

#### 1.2 Request API
- [ ] Request 构造函数
- [ ] Request.clone() 方法
- [ ] 请求属性（url, method, headers, body 等）
- [ ] 请求模式（cors, no-cors, same-origin）
- [ ] 缓存策略支持

#### 1.3 Response API
- [ ] Response 构造函数
- [ ] Response.ok 属性
- [ ] Response.status 和 statusText
- [ ] 响应体读取方法（text(), json(), blob(), arrayBuffer()）
- [ ] Response.clone() 方法
- [ ] 响应类型（basic, cors, error, opaque）

#### 1.4 Headers API
- [x] Headers 构造函数（部分实现）
- [ ] 标准方法：append(), delete(), get(), has(), set()
- [ ] 迭代器支持：entries(), keys(), values()
- [ ] 大小写不敏感处理
- [ ] 受保护头部处理

#### 1.5 URL API
- [x] URL 构造函数（部分实现）
- [ ] URL 属性（protocol, host, pathname, search, hash 等）
- [ ] URL.searchParams 属性
- [ ] 相对 URL 解析

#### 1.6 URLSearchParams API
- [x] URLSearchParams 构造函数（部分实现）
- [ ] 标准方法：append(), delete(), get(), getAll(), has(), set()
- [ ] 迭代器支持：entries(), keys(), values()
- [ ] toString() 序列化

#### 1.7 FormData API
- [ ] FormData 构造函数
- [ ] 文件上传支持
- [ ] 标准方法：append(), delete(), get(), getAll(), has(), set()
- [ ] 迭代器支持

#### 1.8 Blob API
- [ ] Blob 构造函数
- [ ] MIME 类型支持
- [ ] slice() 方法
- [ ] stream() 方法

### 2. 高级功能

#### 2.1 流处理
- [ ] ReadableStream 支持
- [ ] 分块传输编码
- [ ] 背压处理
- [ ] 流取消机制

#### 2.2 中止控制
- [ ] AbortController 实现
- [ ] AbortSignal 传播
- [ ] 超时控制
- [ ] 请求取消

#### 2.3 缓存机制
- [ ] HTTP 缓存策略
- [ ] Cache API 实现
- [ ] ETag 支持
- [ ] 条件请求

#### 2.4 安全功能
- [ ] CORS 预检请求
- [ ] CSP 兼容性
- [ ] 安全头部验证
- [ ] 凭据模式控制

### 3. 平台特性

#### 3.1 Web 平台
- [ ] 浏览器原生 Fetch 集成
- [ ] Service Worker 兼容性
- [ ] 浏览器安全策略遵循

#### 3.2 Native 平台
- [ ] HTTP/2 支持
- [ ] 证书验证
- [ ] 代理支持
- [ ] 连接池管理

## API 设计

### 1. 核心 API 结构

```dart
// 主要导出
export 'src/fetch.dart' show fetch;
export 'src/request.dart' show Request, RequestInit;
export 'src/response.dart' show Response;
export 'src/headers.dart' show Headers;
export 'src/url.dart' show URL;
export 'src/url_search_params.dart' show URLSearchParams;
export 'src/form_data.dart' show FormData;
export 'src/blob.dart' show Blob;
export 'src/abort.dart' show AbortController, AbortSignal;
```

### 2. Fetch 函数设计

```dart
// 基础 fetch 函数
Future<Response> fetch(RequestInfo input, [RequestInit? init]);

// RequestInfo 类型
abstract class RequestInfo {
  const RequestInfo();
  factory RequestInfo.url(String url) = _RequestInfoUrl;
  factory RequestInfo.request(Request request) = _RequestInfoRequest;
}

// RequestInit 配置
class RequestInit {
  final String? method;
  final HeadersInit? headers;
  final BodyInit? body;
  final String? mode;
  final String? credentials;
  final String? cache;
  final String? redirect;
  final String? referrer;
  final String? referrerPolicy;
  final String? integrity;
  final bool? keepalive;
  final AbortSignal? signal;

  const RequestInit({
    this.method,
    this.headers,
    this.body,
    this.mode,
    this.credentials,
    this.cache,
    this.redirect,
    this.referrer,
    this.referrerPolicy,
    this.integrity,
    this.keepalive,
    this.signal,
  });
}
```

### 3. Request 类设计

```dart
class Request {
  // 构造函数
  Request(RequestInfo input, [RequestInit? init]);

  // 只读属性
  String get url;
  String get method;
  Headers get headers;
  String get mode;
  String get credentials;
  String get cache;
  String get redirect;
  String get referrer;
  String get referrerPolicy;
  String get integrity;
  bool get keepalive;
  AbortSignal? get signal;

  // Body 相关属性
  bool get bodyUsed;

  // 方法
  Request clone();

  // Body 读取方法
  Future<Uint8List> arrayBuffer();
  Future<Blob> blob();
  Future<FormData> formData();
  Future<dynamic> json();
  Future<String> text();
}
```

### 4. Response 类设计

```dart
class Response {
  // 构造函数
  Response(BodyInit? body, [ResponseInit? init]);
  Response.error();
  Response.redirect(String url, [int status = 302]);

  // 只读属性
  String get type;
  String get url;
  bool get redirected;
  int get status;
  bool get ok;
  String get statusText;
  Headers get headers;

  // Body 相关属性
  bool get bodyUsed;

  // 方法
  Response clone();

  // Body 读取方法
  Future<Uint8List> arrayBuffer();
  Future<Blob> blob();
  Future<FormData> formData();
  Future<dynamic> json();
  Future<String> text();
}
```

### 5. Headers 类设计

```dart
class Headers {
  // 构造函数
  Headers([HeadersInit? init]);

  // 方法
  void append(String name, String value);
  void delete(String name);
  String? get(String name);
  bool has(String name);
  void set(String name, String value);

  // 迭代器
  Iterable<String> keys();
  Iterable<String> values();
  Iterable<List<String>> entries();

  // Dart 特有
  void forEach(void Function(String value, String name) callback);
  Map<String, String> toMap();
}

// HeadersInit 类型联合
abstract class HeadersInit {
  const HeadersInit();
  factory HeadersInit.map(Map<String, String> map) = _HeadersInitMap;
  factory HeadersInit.headers(Headers headers) = _HeadersInitHeaders;
  factory HeadersInit.list(List<List<String>> list) = _HeadersInitList;
}
```

### 6. URL 类设计

```dart
class URL {
  // 构造函数
  URL(String url, [String? base]);

  // 属性
  String get href;
  set href(String value);

  String get origin;

  String get protocol;
  set protocol(String value);

  String get username;
  set username(String value);

  String get password;
  set password(String value);

  String get host;
  set host(String value);

  String get hostname;
  set hostname(String value);

  String get port;
  set port(String value);

  String get pathname;
  set pathname(String value);

  String get search;
  set search(String value);

  URLSearchParams get searchParams;

  String get hash;
  set hash(String value);

  // 方法
  String toString();
  String toJSON();

  // 静态方法
  static bool canParse(String url, [String? base]);
}
```

### 7. URLSearchParams 类设计

```dart
class URLSearchParams {
  // 构造函数
  URLSearchParams([URLSearchParamsInit? init]);

  // 方法
  void append(String name, String value);
  void delete(String name, [String? value]);
  String? get(String name);
  List<String> getAll(String name);
  bool has(String name, [String? value]);
  void set(String name, String value);
  void sort();

  // 迭代器
  Iterable<String> keys();
  Iterable<String> values();
  Iterable<List<String>> entries();

  // Dart 特有
  void forEach(void Function(String value, String name) callback);
  int get size;

  // 序列化
  String toString();
}
```

### 8. FormData 类设计

```dart
class FormData {
  // 构造函数
  FormData();

  // 方法
  void append(String name, String value);
  void append(String name, Blob blob, [String? filename]);
  void delete(String name);
  String? get(String name);
  List<FormDataEntryValue> getAll(String name);
  bool has(String name);
  void set(String name, String value);
  void set(String name, Blob blob, [String? filename]);

  // 迭代器
  Iterable<String> keys();
  Iterable<FormDataEntryValue> values();
  Iterable<List<dynamic>> entries();

  // Dart 特有
  void forEach(void Function(FormDataEntryValue value, String name) callback);
}

// FormDataEntryValue 类型联合
abstract class FormDataEntryValue {
  const FormDataEntryValue();
}

class FormDataEntryString extends FormDataEntryValue {
  final String value;
  const FormDataEntryString(this.value);
}

class FormDataEntryFile extends FormDataEntryValue {
  final Blob blob;
  final String? filename;
  const FormDataEntryFile(this.blob, this.filename);
}
```

### 9. AbortController 设计

```dart
class AbortController {
  // 构造函数
  AbortController();

  // 属性
  AbortSignal get signal;

  // 方法
  void abort([dynamic reason]);
}

class AbortSignal {
  // 静态方法
  static AbortSignal abort([dynamic reason]);
  static AbortSignal timeout(Duration timeout);

  // 属性
  bool get aborted;
  dynamic get reason;

  // 方法
  void throwIfAborted();

  // 事件
  void addEventListener(String type, EventListener listener);
  void removeEventListener(String type, EventListener listener);
}
```

## 错误处理

### 1. 错误类型

```dart
// 网络错误
class NetworkError extends Error {
  final String message;
  NetworkError(this.message);
}

// 中止错误
class AbortError extends Error {
  final dynamic reason;
  AbortError(this.reason);
}

// 类型错误
class TypeError extends Error {
  final String message;
  TypeError(this.message);
}

// 语法错误
class SyntaxError extends Error {
  final String message;
  SyntaxError(this.message);
}
```

### 2. 错误处理策略

- 网络失败抛出 `NetworkError`
- 请求被中止抛出 `AbortError`
- 无效参数抛出 `TypeError`
- JSON 解析失败抛出 `SyntaxError`

## 平台实现策略

### 1. 条件导出

```dart
// lib/src/fetch.dart
export 'fetch.native.dart'
    if (dart.library.js_interop) 'fetch.web.dart'
    show fetch;
```

### 2. Web 平台实现

- 直接使用浏览器原生 Fetch API
- 通过 JS Interop 实现
- 保持完全的行为一致性

### 3. Native 平台实现

- 使用 `dart:io` HttpClient
- 实现 Fetch API 语义
- 添加平台特有的优化

## 性能考虑

### 1. 内存管理

- 流式处理大文件
- 及时释放资源
- 避免内存泄漏

### 2. 网络优化

- 连接复用
- 压缩支持
- 超时控制

### 3. 缓存策略

- HTTP 缓存头遵循
- 条件请求支持
- 本地缓存实现

## 测试策略

### 1. 单元测试

- 每个 API 的功能测试
- 边界条件测试
- 错误场景测试

### 2. 集成测试

- 跨平台兼容性测试
- 真实网络请求测试
- 性能基准测试

### 3. 合规性测试

- Web Platform Tests (WPT) 集成
- 标准合规性验证
- 浏览器兼容性测试

## 发布计划

### Phase 1: 核心 APIs (v0.1.0)
- [ ] Headers API
- [ ] URL API
- [ ] URLSearchParams API
- [ ] 基础 fetch() 函数
- [ ] Request/Response 核心功能

### Phase 2: 高级功能 (v0.2.0)
- [ ] 完整的 Body 处理
- [ ] FormData API
- [ ] Blob API
- [ ] 流处理支持

### Phase 3: 企业特性 (v0.3.0)
- [ ] AbortController
- [ ] 缓存机制
- [ ] 高级安全特性
- [ ] 性能优化

### Phase 4: 生产就绪 (v1.0.0)
- [ ] 完整的测试覆盖
- [ ] 性能基准
- [ ] 文档完善
- [ ] 生态系统集成

## 社区和生态

### 1. 文档

- API 参考文档
- 迁移指南
- 最佳实践
- 示例代码

### 2. 工具支持

- IDE 插件
- 调试工具
- 代码生成器
- 测试工具

### 3. 生态集成

- 流行框架适配
- 中间件生态
- 插件系统
- 社区贡献

---

本文档将随着项目进展持续更新，确保需求和设计的及时性和准确性。
