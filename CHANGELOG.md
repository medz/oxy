## Unreleased

### Changed

- Upgraded to `ht ^0.4.0`.
- Removed `ht.Body` as an accepted Oxy body source; use stable data
  containers such as `Blob` instead.

## 0.4.0

### Breaking Changes

- Removed middleware presets; compose middleware explicitly from the built-in
  middleware types instead.
- Redesigned middleware around lifecycle capabilities. `Middleware.intercept`
  and `Next` were replaced by request, attempt, final response, error, and
  finally capability interfaces.
- Deprecated `ClientOptions.networkMiddleware` and
  `RequestOptions.networkMiddleware`; configure common middleware through the
  primary `middleware` list instead.

### Added

- Added public API Dartdoc, a cookbook, and checked examples for reusable API
  clients, policies, no-throw flows, middleware, testing, and body
  replayability.
- `CookieMiddleware` now works across redirects and retries from the primary
  `middleware` list.

## 0.3.0

### Breaking Changes

- Rebuilt Oxy around semantic core types: `Client`, `Request`, `Response`,
  `Headers`, `Body`, policy types, middleware, typed errors, and `Result`.
- Removed `ht.Request`/`ht.Response` as Oxy's public request model along with
  the old `Oxy`/`OxyConfig` API shape.
- Replaced the `safe*` method matrix with unified result flows:
  `Result.capture(...)`, `Client.sendResult(...)`, `Client.requestResult(...)`,
  and `fetchResult(...)`.
- Status handling now uses `StatusPolicy`; non-2xx responses throw
  `StatusError` by default.

### Added

- Built-in native, web, and test transports under Oxy's own single-package
  transport layer.
- `Context` with typed `Attributes` for middleware coordination.
- Replayability-aware `Body` and `ResponseBody` primitives.
- Selective `ht` body-helper integration for `Blob`, `FormData`, `Multipart`,
  and `URLSearchParams` without exposing `ht.Request`/`ht.Response` as Oxy's
  request model.
- Hardened cookie scope validation, cache revalidation, browser forbidden
  headers, timeout enforcement, retry draining, and error-body preview handling.
- Added client-level native/test redirect following, explicit web redirect-limit
  policy errors, JSON `null` request bodies, and stronger middleware error
  normalization.
- Application and network middleware layers.
- Policy-driven timeout, retry, redirect, and status behavior.
- `MockTransport` via `package:oxy/testing.dart`.

### Changed

- Native clients keep connections alive by default and expose explicit
  `Client.close()` lifecycle management.
- Middleware now works with immutable/copy-on-write requests instead of
  mutating shared request instances.
- Cache, cookie, auth, logging, and request-id features remain in the single
  package but sit behind the common middleware pipeline.

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
