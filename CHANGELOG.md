## Unreleased

## 0.2.2

### Fixed

- Restored browser compatibility for non-stream request bodies by avoiding accidental request streaming on HTTP/1.1 endpoints.
- Preserved the intended web body transport mode for manual `send(Request(...))` calls and hardened invalid internal body-mode metadata handling.
- Added browser regression coverage for JSON POST requests and manual request-body mode handling.

## 0.2.1

### Fixed

- Raised the `ht` lower bound to `^0.3.1` to avoid resolving the broken `ht 0.3.0` release.
- Updated Oxy request construction to match the corrected `ht 0.3.1` `Request(Object? input, [RequestInit? init])` API.
- Refreshed README snippets and public API tests for the `ht 0.3.1` hotfix line.

## 0.2.0

### Breaking Changes

- Upgraded to `ht 0.3` and aligned Oxy request/response APIs with the new `ht` request and response semantics.
- Low-level request construction now follows the `ht 0.3` model, including `RequestInput.*`, `RequestInit`, `HttpMethod`, and `HeadersInit`-based inputs where applicable.
- Middleware now forwards and mutates the active `Request` instance instead of depending on copied request objects. Custom middleware that relied on copy-on-write behavior should update to mutate the provided request before calling `next`.
- Re-exported cookie types now follow `ocookie 0.2.0` two-state flag semantics. `Cookie.httpOnly`, `Cookie.secure`, and `Cookie.partitioned` now default to `false`, and `CookieNullableField.httpOnly`, `CookieNullableField.secure`, and `CookieNullableField.partitioned` are no longer available.

### Changed

- Upgraded dependencies to `ht ^0.3.0` and `ocookie ^0.2.0`.
- Updated examples, README snippets, and test coverage for the `ht 0.3` request construction model.
- Aligned transport, cache, logging, auth, request ID, and cookie middleware behavior with the latest `ht` header and response APIs.

### Fixed

- Preserved request `Cookie` header precedence over cookie jar values when merging cookies in `CookieMiddleware`.
- Kept cookie parsing aligned with `ocookie 0.2.0`, including explicit `Secure=false`, `HttpOnly=false`, and `Partitioned=false` flag handling.
- Removed unnecessary request copying inside the middleware pipeline while preserving request mutation behavior across built-in middleware.

## 0.1.0

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
