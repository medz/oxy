## Unreleased

- Redesigned core request pipeline with clearer error model and retry flow.
- Added official middleware set: `AuthMiddleware`, `CookieMiddleware`,
  `CacheMiddleware`, `LoggingMiddleware`, `RequestIdMiddleware`.
- Added `OxyPresets.standard(...)` for recommended middleware composition,
  with optional toggles and middleware overrides.
- Added `OxyPresets.minimal(...)` and `OxyPresets.full(...)` for
  low/high complexity middleware composition.
- Added fluent preset helpers:
  `OxyConfig.withPreset/withMinimalPreset/withStandardPreset/withFullPreset`
  and
  `Oxy.withPreset/withMinimalPreset/withStandardPreset/withFullPreset`.
- Decoupled cookie read/write from core send path into dedicated middleware.
- Switched cookie model to `ocookie.Cookie` directly and removed
  `OxyCookie` wrapper type.
- Removed `OxyConfig.cookieJar` and implicit cookie middleware injection.
  Cookie support is now explicit via `CookieMiddleware` or presets.
- Added safe API layer:
  `safeGet/safePost/safePut/safePatch/safeDelete/safeHead/safeOptions`,
  plus decoded variants and top-level `safeFetch*` helpers.
- Added `Response.decode<T>()` extension and unified typed decode behavior.
- Expanded test coverage for middleware composition, cookie auto-injection,
  safe API behavior, and upload/download progress callbacks.

## 0.1.0

- Rebuilt `oxy` on top of `ht` types.
- Removed adapter architecture and adapter packages from this repository.
- Added built-in transport layer for VM/Web with `FetchOptions`.
- Added redirect policy, keep-alive, timeout, and abort integration.

## 0.0.4

- First public preview.
