# Oxy 重写调研报告：现代请求库的产品与架构形态

调研时间：2026-06-18（Asia/Shanghai）

范围：本报告只做产品与架构研究，不涉及代码实现。调研对象包括 Oxy 当前仓库，以及 JavaScript/TypeScript、Python、Rust、Go、JVM/Kotlin、Swift、.NET 中有代表性的现代请求库。本文按新的重写目标修订：**核心类型不做 Oxy 品牌前缀、单包交付、Oxy 默认天然跨平台且高性能、不把其他 Dart HTTP 包作为 Oxy transport 范畴。**

## 重新设计后的目标

Oxy 的目标不是成为一组 HTTP adapter，也不是成为某个现有 Dart HTTP 包的上层封装。Oxy 应该是一个独立、单包、默认跨平台、默认高性能的现代请求库。

最终定位：

> Oxy 是 Dart 和 Flutter 生态的现代请求库：以 `Client`、`Request`、`Response`、`Headers`、`Body`、`Error`、`Policy`、`Middleware` 为核心概念，在一个包内提供 VM、Flutter、Web 一致的请求体验、性能默认值和可扩展架构。

最关键的产品约束：

1. **核心类型不带 Oxy 品牌前缀**：不要 `OxyClient`、`OxyRequest`、`OxyResponse`。包名已经是命名空间，公开核心类型应直接叫 `Client`、`Request`、`Response`、`Headers`、`Body`、`Options`、`Policy`、`Transport`、`Context`。
2. **单包交付**：不规划 `oxy_http_adapter`、`oxy_cache`、`oxy_cookie`、`oxy_otel` 等 companion packages。可以有清晰内部模块和可选 imports，但用户安装一个 `oxy` 包就应得到完整一等体验。
3. **天然跨平台**：跨平台不是外部 adapter 能力，而是 Oxy 的默认事实。VM、Flutter Native、Flutter Web、Dart Web 都应由同一公开 API 覆盖。
4. **默认高性能**：高性能不是高级配置项。可复用 client、连接复用、streaming、低内存 decode、有限 body preview、明确 close 生命周期、重试 jitter、不可重放 body 保护，都应是默认架构的一部分。
5. **不把其他 Dart HTTP 包写成传输层方向**：Oxy 不应把 `package:http` 之类作为重写路线的一部分。可以从其他生态学习 client/transport 分层，但 Oxy 的 transport 应是自己内建的 native/web 平台实现。`ht` 这类成熟 primitives 可以被选择性复用为内部或 body-helper 基础，但不能把 Oxy 的公开 `Request/Response` ABI 锁死到第三方类型。
6. **心智模型小，但架构完整**：用户只学一套路径：`Client -> Request -> Middleware/Policy -> Transport -> Response/Error`。复杂能力沿着这条路径扩展。

## 一句话结论

Oxy 重写应该做成 **Fetch 心智模型 + HTTPX/Go/.NET 的 client 生命周期纪律 + OkHttp 的拦截器边界 + Ky/ofetch 的易用默认 + Dio 的 Flutter 实用能力**，但最终产品形态必须是 Oxy 自己的一套单包架构。

如果只能保留一句原则：

> Oxy 应该让简单请求自然，让复杂请求可解释，让平台差异可见，让性能默认正确。

## 当前 Oxy 的基础与问题

当前仓库已经有不少可保留的方向：

- 以 client 和 fetch-style API 为入口。
- 使用 Fetch-like 的 `Request`、`Response`、`Headers`。
- 有 `RequestOptions`、retry、timeout、abort、redirect policy、HTTP error policy。
- 有 middleware pipeline。
- 有 safe result API。
- 有 native/web 条件导入 transport。
- 有 auth、cookie、cache、logging、request id 等 middleware。
- 测试覆盖 public API、VM/browser、abort、decode、middleware、result、cookie/cache/presets。

重写时需要修正的问题：

### 1. 主类型命名要回到无品牌前缀

当前主入口叫 `Oxy`，未来如果设计成 `OxyClient`、`OxyRequest` 会继续放大品牌噪音。更理想的公开模型是：

- `Client`
- `Request`
- `Response`
- `Headers`
- `Body`
- `Options`
- `Policy`
- `Middleware`
- `Context`
- `Result`

错误类型也应尽量描述语义而非品牌，例如：

- `RequestError`
- `NetworkError`
- `TimeoutError`
- `CancelError`
- `StatusError`
- `DecodeError`
- `RetryError`
- `MiddlewareError`

包名 `oxy` 已经提供语境。用户如果与其他库冲突，可以通过 Dart import alias 解决；库本身不应该把所有核心类型都加前缀。

### 2. API 方法矩阵要收敛

当前每个 method 都有 throw 版、safe 版、decoded 版，形成 `get`、`safeGet`、`getDecoded`、`safeGetDecoded`、`fetch`、`safeFetch`、`fetchDecoded` 等矩阵。重写后应收敛成：

- method helper 只负责构造和发送请求。
- response 负责 bytes/text/json/stream decode。
- status policy 统一决定是否抛 `StatusError`。
- result 模式通过统一 wrapper 进入，不复制所有 method。

目标不是“少功能”，而是“少入口”。高级能力应该是同一条路径上的参数、policy 或 middleware，而不是另一组 API。

### 3. 当前 transport 生命周期不够产品化

当前 native transport 使用全局 `HttpClient`，公开层没有完整的 client lifecycle、close、连接池策略、idle timeout、DNS/TLS 生命周期、并发限制等主线。`keepAlive` 默认 false 也不符合现代请求库的性能目标。

重写后必须以 `Client` 生命周期为中心：

- `Client` 是生产主入口。
- `Client` 默认复用连接。
- `Client` 可关闭。
- top-level helper 只适合脚本和一次性请求。
- native/web 都遵循同一个外部语义。
- 平台能力差异通过 capability 和文档呈现。

### 4. retry 必须理解 body 可重放性

当前 retry 对 prepared request 反复发送。stream body 第一次消费后通常不可重放。现代设计必须把 body 分成：

- always replayable：empty、bytes、string、json、form。
- conditionally replayable：file、multipart，可通过 body factory 或 reopen 策略重放。
- non-replayable：任意一次性 stream。

默认策略：

- 不重试不可重放 body。
- 默认只重试幂等方法。
- POST/PATCH 只有显式 opt-in、idempotency key 或 replayable body factory 时才重试。
- retry hook 能告诉用户为什么跳过重试。

### 5. middleware 要从简单函数链升级为完整 pipeline

当前 `intercept(request, options, next)` 足够简单，但不够完整：

- 不区分应用层 request 与每次网络 attempt。
- 不区分 request、response、error、retry、finally 阶段。
- `extra` 是字符串 key map，不适合做长期扩展基础。
- body 所有权、response stream 消费、短路规则都需要协议化。

重写应保留一个小的 middleware 心智，但底层要有清楚阶段：

- application middleware：看到逻辑请求，只执行一次。
- network middleware：每个网络 attempt 执行一次。
- lifecycle hooks：覆盖常见 onRequest/onResponse/onError/onRetry/onFinally。
- queued middleware：处理 token refresh、CSRF refresh 等必须串行的场景。

### 6. cache/cookie/logging 要留在单包内，但不能污染核心

用户希望单包，所以 cache、cookie、logging、observability 不应被拆成独立包。但它们仍要在架构上与核心隔离：

- 核心是 `Client/Request/Response/Body/Error/Policy/Pipeline/Transport`。
- 功能模块在同包内以独立 namespace、文件夹或 export 分区存在。
- 默认开启项必须非常克制。
- heavy 行为必须 opt-in。
- 所有功能都通过同一 pipeline，不走特殊私有通道。

## 竞品启发

### Fetch

Fetch 的价值是心智模型小：`Request`、`Response`、`Headers`、body stream。Oxy 应借鉴这个对象模型，因此公开类型也应直接叫 `Request`、`Response`、`Headers`，不加品牌前缀。

Fetch 的不足是缺少 timeout、retry、base URL、JSON convenience、middleware、status validation。Oxy 要补齐这些应用层能力。

### Ky

Ky 说明现代请求库可以很小但非常舒服：prefix URL、search params、timeout、retry、hooks、typed HTTP error、`.json()`。它的启发是：默认能力要高质量，API 不需要大而全。

Oxy 应学习它的轻入口和 retry/hook 表达力，但用 Dart 类型和 body replay 规则把边界做得更稳。

### ofetch

ofetch 的启发是跨 runtime 默认可用、JSON body/response 默认顺手、raw escape hatch 保留。Oxy 也应天然跨平台，但不应把跨平台表现描述为“接不同 adapter”，而应描述为 Oxy 自己内建 native/web runtime。

### Axios

Axios 证明业务开发者需要 instance defaults、interceptors、status validation、progress、adapter-style boundary、structured error。Oxy 可以吸收 instance defaults、status policy、interceptor、progress，不要吸收过大的配置面。

### Dio

Dio 是 Flutter 生态强功能 HTTP client 的代表。它证明 Flutter 用户确实需要 interceptors、FormData、cancel、upload/download progress、transformer、adapter、queued interceptor。

Oxy 的机会不是复制 Dio，而是在更小模型内提供这些能力：

- `Client` 管 defaults。
- `Request` 管输入。
- `Body` 管上传形态。
- `Middleware` 管扩展。
- `Policy` 管 retry/timeout/status/redirect。
- `Response` 管读取和 decode。

### HTTPX / Requests

Requests 的启发是“常见 HTTP 行为命名清楚”。HTTPX 的启发是 `Client`、strict timeout、connection pooling、sync/async 统一体验、transport abstraction、typed API。

对 Oxy 来说，最重要的是：`Client` 是性能、配置、生命周期、连接池和默认值的中心。生产路径不应该鼓励每次创建一次性 client。

### Go net/http

Go 的 `Client`、`Transport`、`RoundTripper` 分层值得学习，但不是为了复刻 Go，也不是为了接入其他 Dart HTTP 包。它提醒 Oxy：

- client 管用户可见策略。
- transport 管一次真实网络发送。
- transport 必须可被内部 mock，便于测试。
- client 应并发安全。
- connection pool 是 client/transport 生命周期的一部分。

### OkHttp

OkHttp 的启发最关键：

- 默认高性能。
- client 拥有连接池。
- interceptor 分应用层和网络层。
- response body ownership 必须明确。
- redirect/retry 会影响 interceptor 观察到的次数。

Oxy 的 middleware 设计应该直接吸收这些边界，而不是只提供一个通用 next 函数。

### reqwest / ureq

reqwest 展示了高层 Client + RequestBuilder + feature-controlled 能力，ureq 展示了简单同步客户端的低依赖方向。Dart 没有同样的 feature flags，且本次目标是单包，所以 Oxy 应在单包内通过清晰模块和 opt-in policies 控制复杂度，而不是拆包。

### Ktor / Retrofit / Alamofire / .NET

Ktor 的 plugin/engine 思想说明跨平台客户端需要运行时能力矩阵。Retrofit 说明 typed endpoint 可以作为上层模式，但不应进入核心。Alamofire 说明 cURL 输出、validation、retry/adapt、progress、TLS 这类产品细节很重要。.NET 则提醒 client 生命周期、connection pool、DNS 更新和端口耗尽不是边角问题。

Oxy 的结论：单包内保留完整工程架构，但不要让 generator、reachability、平台专属 TLS pinning 之类高级产品吞掉核心心智。

## 目标公开 API 模型

### 命名原则

公开核心类型使用无品牌名：

- `Client`
- `ClientOptions`
- `Request`
- `RequestOptions`
- `Response`
- `ResponseBody`
- `Headers`
- `Body`
- `BodyKind`
- `Policy`
- `StatusPolicy`
- `RetryPolicy`
- `TimeoutPolicy`
- `RedirectPolicy`
- `Middleware`
- `Interceptor`
- `Context`
- `Result`
- `RequestError`

品牌只出现在包名、文档标题、日志默认前缀、User-Agent 默认值中。

### 用户入口

推荐三层入口：

1. **主入口 `Client`**：生产推荐路径，持有配置、连接池、pipeline、默认 policy。
2. **轻量 top-level helpers**：适合脚本、demo、一次性请求，但文档明确生产热路径应使用 `Client`。
3. **prepared `Request`**：适合 SDK、签名、复杂 body、stream、测试、重放控制。

不要继续扩大 safe/decoded method 矩阵。no-throw 是 result 模式；decode 是 response 能力；method helper 是请求入口。

### 默认行为

建议默认：

- 非 2xx 由 `StatusPolicy` 触发 `StatusError`。
- 用户可关闭 status validation，得到所有 response。
- network/timeout/cancel/decode/status 都是可区分 error。
- request timeout 有默认值。
- native 默认连接复用。
- retry 默认保守开启，只重试安全场景。
- body 不被日志/cache/error preview 隐式无限读取。
- web/native 使用同一 API，但 capability 说明差异。

## 完整架构设计

### 总体分层

Oxy 单包内部建议分成十个逻辑层。它们可以都在一个 package 内，但边界必须清晰。

1. **Public Facade**
   - `oxy.dart` 的公开 export。
   - 只暴露稳定核心类型、默认 middleware、policies、testing primitives。

2. **Core Primitives**
   - `Client`
   - `Request`
   - `Response`
   - `Headers`
   - `Body`
   - `ResponseBody`
   - `Result`
   - error hierarchy

3. **Options Resolution**
   - 合并 global defaults、client options、request options。
   - 产出不可变 `Context`。
   - 负责 header/query/baseUrl/body metadata 归一化。

4. **Policy Engine**
   - timeout/deadline
   - retry
   - redirect
   - status validation
   - decode
   - cache
   - cookies
   - auth

5. **Application Pipeline**
   - 用户逻辑层 middleware。
   - 执行一次。
   - 适合 auth、request id、business headers、result mapping、mock short-circuit。

6. **Operation Controller**
   - 管理一次逻辑请求的完整生命周期。
   - 持有 abort/deadline。
   - 驱动 retry loop。
   - 发出事件。

7. **Network Pipeline**
   - 每个 attempt 执行。
   - 适合低层日志、metrics、redirect/retry 观察、wire-level headers。

8. **Platform Transport**
   - Oxy 内建 native transport。
   - Oxy 内建 web fetch transport。
   - 测试 transport。
   - 不规划外部 Dart HTTP 包 transport。

9. **Feature Modules**
   - auth
   - cookie jar
   - cache store
   - logging
   - cURL exporter
   - observability
   - multipart/form data
   - presets

10. **Testing Utilities**
    - mock transport
    - request recorder
    - fake clock
    - deterministic retry scheduler
    - response builder

### 请求生命周期

一次请求应按以下顺序流动：

1. 用户调用 `Client` method 或传入 prepared `Request`。
2. facade 创建或接收 `Request`。
3. options resolver 合并 client defaults 与 request overrides。
4. URL/baseUrl/query/header/body 被归一化。
5. 创建 `Context`：request id、deadline、abort signal、attempt counter、attributes、events。
6. application request middleware 执行。
7. operation controller 进入 retry loop。
8. 对当前 attempt 检查 body replayability。
9. network request middleware 执行。
10. platform transport 发送请求。
11. network response middleware 执行。
12. retry policy 判断 response/error 是否需要 retry。
13. status policy 判断是否抛 `StatusError`。
14. application response middleware 执行。
15. 用户读取 `Response` body 或触发 decode。
16. onFinally/metrics/logging 收尾。
17. 如果用户选择 result 模式，error 被包进 `Result`，否则按 typed error 抛出。

这个生命周期的关键是：**application 层看一次逻辑请求，network 层看每次真实发送。**

### Context 设计

`Context` 是内部架构稳定的关键，应该替代字符串 key `extra` 成为扩展基础。

它应包含：

- request id
- attempt index
- createdAt
- deadline
- abort signal
- client options snapshot
- resolved request metadata
- body replayability
- platform capability
- attributes typed map
- event emitter
- redaction policy
- retry state
- timing state

attributes 应支持 typed key，不用裸字符串，避免 middleware 之间撞 key。

### Request 设计

`Request` 应是不可变或 copy-on-write：

- method
- uri
- headers
- body
- options override
- attributes

归一化后不应悄悄修改用户传入的原 request。middleware 如果要改 request，应返回新 request 或使用明确的 builder/copy。

Request body 必须携带：

- body kind
- content length 是否已知
- content type 是否已知
- 是否 replayable
- 是否已被消费
- clone/reopen 能力

### Response 设计

`Response` 应表达：

- status
- status text
- headers
- final url
- redirected
- body stream
- timing metadata
- attempt metadata
- fromCache
- trailers（平台支持时）

Response body 默认单次消费。`bytes()`、`text()`、`json()` 都是读取行为。需要 clone/tee 时必须显式，且受大小与平台能力限制。

### Body 设计

body 是性能和 retry 正确性的中心。建议内置：

- empty
- bytes
- text
- json
- form urlencoded
- multipart
- file
- stream
- factory/replayable stream

规则：

- json/form/text/bytes 默认可重放。
- stream 默认不可重放。
- file 是否可重放取决于 reopen 实现。
- multipart 是否可重放取决于各 part。
- retry/cache/logging 不得隐式消费不可重放 body。

### Error 设计

错误层级建议按语义拆：

- `RequestError`：所有请求错误基类。
- `NetworkError`：DNS、socket、TLS、connection reset 等。
- `TimeoutError`：包含 phase 和 duration/deadline。
- `CancelError`：用户取消或 deadline/cascade cancel。
- `StatusError`：有 response，status validation 失败。
- `DecodeError`：response body decode 或 typed mapping 失败。
- `RetryError`：retry exhausted，保留 last error/response/attempts。
- `MiddlewareError`：middleware 抛错，保留 middleware 标识和 cause。

每个 error 应回答：

- 是否有 request？
- 是否有 response？
- 是否已经发送到网络？
- 是否可重试？
- 是否用户主动取消？
- 是否保留 body preview？

### Policy 设计

所有可变行为进入 policy，不散落在各个 method 参数里。

#### StatusPolicy

- 默认 2xx 成功。
- 可配置允许 3xx/4xx。
- 可关闭，返回所有 response。
- `StatusError` 保留 response 和有限 body preview。

#### TimeoutPolicy

支持：

- connect timeout
- send timeout
- first byte timeout
- read timeout
- total timeout/deadline
- per-attempt timeout
- whole-operation timeout

平台不能支持的 phase 要在 capability 中标记，不要假装支持。

#### RetryPolicy

默认：

- 幂等方法可重试。
- 408、429、500、502、503、504 可重试。
- network/timeout 可重试。
- 支持 `Retry-After`。
- exponential backoff + jitter。
- 不重试不可重放 body。
- 用户取消不重试。
- decode error 不重试。

#### RedirectPolicy

- follow
- manual
- error
- max redirects
- redirect hooks
- method rewrite 规则明确，例如 303。

#### DecodePolicy

- 默认不强制 decode。
- `json<T>` 需要 decoder 或显式 cast 规则。
- 大 body 不隐式全量读。
- 错误 preview 有上限。

#### CachePolicy

单包内可以有 cache，但默认不开启复杂缓存。建议：

- core 提供 policy 和 store interface。
- memory cache 可内置。
- production cache 必须支持 `Cache-Control`、`ETag`、`Last-Modified`、`Vary` 的基本正确性。
- cache middleware 必须遵守 body ownership。

#### CookiePolicy

- native 使用 client-owned jar。
- web 依赖 fetch credentials 与浏览器策略。
- cookie jar 默认隔离在 client 内。
- 不做全局共享 cookie。

### Middleware 设计

推荐同时提供两种层次。

#### Lifecycle hooks

适合常见场景：

- onRequest
- onResponse
- onError
- onRetry
- onFinally

这些 hooks 不要求用户理解 chain proceed。

#### Interceptors

适合高级场景：

- application interceptor：一次逻辑请求执行一次，可 short-circuit。
- network interceptor：每个真实 attempt 执行一次，可观察 redirect/retry 后状态。
- queued interceptor：串行执行，适合 token refresh。

interceptor 协议必须明确：

- 是否可以多次 proceed。
- response body 谁负责关闭。
- short-circuit response 是否进入 status policy。
- error 是否进入 retry policy。
- request 修改是否 copy-on-write。

### Observability 设计

Oxy 应内置事件模型，而不是只提供打印日志。

事件包括：

- request start
- request prepared
- application middleware start/end
- retry scheduled/skipped
- network attempt start/end
- headers received
- body progress
- redirect
- status validation failed
- decode start/end
- request end

事件应支持：

- redaction
- request id
- attempt id
- duration
- bytes sent/received
- error cause
- cURL export
- structured logger adapter

OpenTelemetry 不一定要作为第一版能力，但事件模型不能阻止后续接入。

## 单包结构建议

坚持一个 `oxy` 包，但内部按模块组织：

- `lib/oxy.dart`：稳定公开出口。
- `lib/src/core/`：Client、Request、Response、Headers、Body、Result、errors。
- `lib/src/options/`：ClientOptions、RequestOptions、policy options。
- `lib/src/policy/`：timeout、retry、redirect、status、decode、cache、cookie。
- `lib/src/pipeline/`：middleware、interceptor、hooks、context。
- `lib/src/transport/`：native/web/test transport，仅 Oxy 自己的实现。
- `lib/src/features/`：auth、logging、request id、cookie jar、cache store、multipart。
- `lib/src/observability/`：events、redaction、curl、metrics hooks。
- `lib/src/testing/`：mock transport、fake clock、recorded request helpers。

公开 export 应克制：

- 默认 export core、options、policy、middleware、common features。
- testing 可以由 `package:oxy/testing.dart` 导出，但仍在同一个包内。
- web/native 专属内部实现不直接暴露。

这满足单包目标，同时避免一个巨大的无边界 `src/`。

## 平台与性能设计

### Native / Flutter Native

默认目标：

- 连接复用默认开启。
- client 可关闭。
- request/response streaming。
- upload/download progress。
- gzip/deflate/brotli 支持视平台能力。
- TLS/proxy/basic certificate hooks 通过 native transport options 暴露。
- per-host connection limits 可配置。
- idle timeout 可配置。
- DNS/connection lifetime 策略可配置或至少可被 transport 管理。

### Web / Flutter Web

默认目标：

- 使用 browser fetch。
- 复用浏览器网络栈能力。
- response streaming 在支持平台启用。
- upload progress 如平台无法可靠支持，则 capability 明确标记。
- streaming upload 如需要 `duplex: half`，必须被 capability 和 body policy 控制。
- cookie 行为遵循 credentials/CORS。
- 不能支持的 proxy/TLS/cert pinning 不暴露假选项。

### 性能默认值

默认必须正确：

- `Client` 复用连接。
- top-level helper 不作为性能热路径推荐。
- retry 使用 jitter。
- 不隐式 buffer 大 body。
- error preview 有上限。
- logging 默认 redaction。
- cache 默认有容量上限。
- response body 单次消费。
- decode 大 body 可走 chunk/stream 策略，不能阻塞 UI 热路径。
- request timeout 和 total deadline 都有清晰语义。

## 默认功能集

单包下可以内置这些能力，但默认行为要克制。

### 默认开启

- baseUrl
- query merge
- default headers
- request timeout
- status validation
- conservative retry
- cancellation
- request id
- typed errors
- response bytes/text/json helpers
- structured events

### 默认关闭但内置

- auth middleware
- cookie jar
- cache
- verbose logging
- cURL export
- body logging
- multipart advanced options
- queued token refresh helper

这样单包不会牺牲心智模型，也不会牺牲交付完整性。

## 推荐保留、删除、重做

### 保留

- Fetch-like `Request`、`Response`、`Headers` 心智。
- `Client` 作为主入口。
- baseUrl、query、headers、json body、decode helpers。
- typed error/result 方向。
- abort/cancel。
- middleware/preset 方向。
- native/web 条件导入。
- VM/browser 测试。

### 删除或收敛

- `OxyClient`、`OxyRequest`、`OxyResponse` 这类品牌核心类型命名。
- `safeGet/safePost/safeXDecoded` 方法矩阵。
- 公开 API 对第三方 primitive 的强绑定。
- 字符串 key `extra` 作为主要扩展机制。
- logging 直接 `print` 的默认路径。
- keepAlive 默认 false。
- retry 对不可重放 body 的隐式尝试。
- 外部 Dart HTTP 包 adapter 作为路线图内容。
- 多包拆分建议。

### 重做

- `Client` lifecycle、connection pooling、close。
- `Request/Response/Body` 不可变与 consume/clone/replay 规则。
- `Context` 与 typed attributes。
- status/timeout/retry/redirect/decode policy。
- application/network pipeline。
- queued middleware。
- platform capability matrix。
- observability event model。
- cache/cookie/logging 在单包内的模块边界。

## 重写路线

### Phase 1：冻结目标模型

先确认公开核心类型：

- `Client`
- `ClientOptions`
- `Request`
- `RequestOptions`
- `Response`
- `Headers`
- `Body`
- `Context`
- `Policy`
- `Middleware`
- `Result`
- `RequestError`

同时确定：

- 不使用 `OxyClient/OxyRequest` 命名。
- 单包。
- 不规划外部 Dart HTTP 包 transport。
- native/web 是 Oxy 内建平台能力。

### Phase 2：实现内核骨架

最小可用内核：

- `Client` lifecycle。
- native/web internal transport。
- request normalization。
- immutable request/response/body。
- options resolver。
- context。
- typed errors。
- response stream/bytes/text/json。
- status policy。
- timeout policy。
- cancellation。
- mock/test transport。

### Phase 3：实现 operation controller 与 pipeline

核心执行引擎：

- application middleware。
- network middleware。
- lifecycle hooks。
- retry loop。
- body replayability guard。
- redirect policy。
- finally cleanup。
- event emitter。

### Phase 4：内置功能模块

在同包内补齐：

- auth。
- request id。
- cookie jar。
- cache。
- logging。
- cURL export。
- redaction。
- multipart/form data。
- upload/download progress。
- queued token refresh helper。
- presets。

### Phase 5：迁移层与文档

迁移文档必须明确：

- `Oxy` 迁移到 `Client`。
- `OxyException` 迁移到语义 error。
- `safeX` 迁移到统一 result。
- `getDecoded` 迁移到 response decode。
- `RequestOptions.extra` 迁移到 typed attributes/context。
- keep-alive 默认变化。
- retry body replay 规则。
- web/native capability 差异。

## 成功标准

重写成功的 Oxy 应满足：

- 用户只需要理解 `Client/Request/Response/Policy/Middleware/Error`。
- 核心类型没有品牌前缀。
- 安装一个包就得到完整体验。
- 不依赖其他 Dart HTTP 包作为产品架构前提。
- 默认跨 VM、Flutter Native、Web。
- 默认性能正确，生产用户不会踩连接复用、timeout、retry、body buffering 的坑。
- request body replayability 被系统保护。
- application middleware 与 network middleware 语义清楚。
- errors 可区分 network、timeout、cancel、status、decode、retry、middleware。
- cache/cookie/logging/observability 在单包内可用，但不污染核心。
- mock/testing 能力内建。
- 文档能清楚解释平台能力差异。

## 最终推荐

Oxy 应按以下方向重写：

- **公开类型直接叫 `Client`、`Request`、`Response`**，不走 `OxyClient/OxyRequest` 品牌类型。
- **一个包解决问题**，内部模块化，不外部分包化。
- **内建 native/web 平台 transport**，不把其他 Dart HTTP 包 adapter 作为设计路线。
- **默认跨平台、默认高性能**，而不是把这两点留给用户配置。
- **用完整 pipeline 支撑简单 API**：facade 简单，内部有 options resolver、policy engine、operation controller、application/network middleware、platform transport、observability。
- **保留 Fetch-like 心智，但补齐应用请求库必须有的 policy、错误、重试、timeout、decode、cache/cookie/logging 能力**。

这版目标比“轻量 wrapper”更强，也比“大而全配置对象”更克制。它的核心不是功能数量，而是把所有功能安放在一套能长期稳定的架构里。

## 参考资料

- [MDN Fetch API](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API)
- [Axios documentation](https://axios-http.com/docs/intro)
- [Ky README](https://github.com/sindresorhus/ky)
- [ofetch README](https://github.com/unjs/ofetch)
- [Got README](https://github.com/sindresorhus/got)
- [Node.js fetch globals](https://nodejs.org/api/globals.html#fetch)
- [Dart Dio](https://pub.dev/packages/dio)
- [Requests documentation](https://requests.readthedocs.io/en/latest/)
- [HTTPX documentation](https://www.python-httpx.org/)
- [HTTPX Clients](https://www.python-httpx.org/advanced/clients/)
- [aiohttp client quickstart](https://docs.aiohttp.org/en/stable/client_quickstart.html)
- [reqwest documentation](https://docs.rs/reqwest/latest/reqwest/)
- [ureq documentation](https://docs.rs/ureq/latest/ureq/)
- [Go net/http](https://pkg.go.dev/net/http)
- [Resty README](https://github.com/go-resty/resty)
- [OkHttp overview](https://square.github.io/okhttp/)
- [OkHttp interceptors](https://square.github.io/okhttp/features/interceptors/)
- [Ktor client documentation](https://ktor.io/docs/client-create-new-application.html)
- [Retrofit documentation](https://square.github.io/retrofit/)
- [Alamofire README](https://github.com/Alamofire/Alamofire)
- [.NET HttpClient guidelines](https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/http/httpclient-guidelines)
