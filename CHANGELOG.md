## Unreleased

- No changes yet.

## 0.1.0 (Upcoming)

### Breaking Changes

- Rewritten around `ht` with a middleware-first architecture.
- Removed adapter abstraction and old multi-package workspace layout.
- Removed deprecated subpackages and adapter APIs (`oxy_dio`, `oxy_http`, old `use(...)` adapter flow).

### Added

- Unified VM/Web transports with consistent request/response behavior.
- Middleware system with built-ins:
  - `AuthMiddleware`
  - `CookieMiddleware` + `MemoryCookieJar` (via `ocookie`)
  - `CacheMiddleware` + `MemoryCacheStore`
  - `LoggingMiddleware`
  - `RequestIdMiddleware`
- Official presets:
  - `OxyPresets.minimal(...)`
  - `OxyPresets.standard(...)`
  - `OxyPresets.full(...)`
- `safe*` APIs and `OxyResult` for no-throw flows.
- Rich request options: retry, timeout, abort signal, redirect policy, HTTP error policy.

### Changed

- Public API simplified to a single top-level package: `package:oxy/oxy.dart`.
- Examples, docs, and CI updated for the new architecture and browser coverage.

### Fixed

- Native/Web redirect semantics and redirect error handling alignment.
- Web request streaming compatibility (`duplex: 'half'`) and upload progress semantics.
- Cache behavior edge cases (`no-cache`/`no-store`, 304 revalidation merge safety, LRU bounds).
- Cookie expiration/path matching correctness and cross-platform request ID randomness.

## 0.0.4

- First public preview.
