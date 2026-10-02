# Public contract baseline before 1.0

This records the current API and explicit remaining decisions. It does not
declare the API frozen. The [roadmap](roadmap.md) remains the release gate.

## Entry points and upstream surface

`package:oxy/oxy.dart` exposes `Client`, `fetch` and result helpers; core
request/response/body/header/error/result types; options and policies; lifecycle
middleware, hooks, events and context; built-in feature middleware; and the
`Transport` interface and capabilities. `package:oxy/testing.dart` exposes
`MockTransport` separately.

The surface also includes upstream contracts:

- `Headers` and `HeadersInit` are re-exported from `ht`.
- `Body` extends `ht.Body`; body helper exports include `Blob`, `BlobPart`,
  `File`, `FormData`, `Multipart`, and `URLSearchParams`.
- Cookie exports include the complete current `ocookie` entry point.

Those upstream exports must be included in an API freeze review and any
dependency upgrade, rather than treated as implementation-only dependencies.

## Defaults and ownership

| Contract | Current behavior |
| --- | --- |
| SDK | Dart 3.12 or newer; Flutter qualification is version-specific |
| Timeout | Native connect 10s, logical total 30s; other phase limits unset |
| Retry | At most two retries, idempotent methods, selected transient statuses/errors, replayable request bodies |
| Redirect/status | Follow up to 20 redirects where Oxy owns redirect handling; throw outside 2xx by default; Web restrictions apply |
| Request identity | Non-Web default `oxy`; application/header overrides; Web owns wire user-agent |
| Default transport | Client-owned; native keeps connections alive; close is idempotent |
| Custom transport | Caller-owned, including when shared by derived clients |
| Response | Streaming bodies are one-shot; explicit buffering creates replayable bytes |

Request and response fields are final, while `Headers` remains mutable and body
consumption is stateful. `copyWith` copies headers and shares the body unless
replaced. Use a fresh body or `clone()` where the body permits replay; copying
a request/response does not reset a consumed one-shot body.

Response-stream cancellation stops built-in transport reads, including when
the next chunk is pending. Await subscription/iterator cancellation. A paused
consumer does not spend its read-idle budget, while the absolute total deadline
continues after the stream is subscribed. Timeouts use an internal attempt
signal and do not abort the caller's signal.

## Error and lifecycle boundaries

`bytes`, `text`, and `stream` expose body-read failures directly. `json` and
`decode` currently wrap body-read, parsing and cast/mapping failures in
`DecodeError`, retaining the original failure in `cause`. For example, a read
timeout while decoding JSON is `DecodeError(cause: TimeoutError(...))`.
Changing that to a directly thrown timeout/cancellation error would change
what existing catch handlers observe; it needs an explicit decision and
migration examples before the freeze.

Client response/error/finally hooks surround request processing and delivery
of the response. Later lazy body consumption is outside those completed hooks;
handle body failures in the caller or capture the whole operation:

```dart
final result = await Result.capture(() async {
  final response = await client.get('/users');
  return response.json<List<Object?>>();
});
```

The capability-based pipeline distinguishes logical request transforms and
resolvers, per-attempt transforms/responses, and final response/error/finally
handlers. Order and short-circuit/retry/redirect behavior must remain covered
by pipeline regressions before being frozen.

## Remaining gates

Retain executable examples and freeze the complete export/default/error/hook
surface, including upstream types. Decide JSON body-error handling deliberately.
Resolve cold macOS automatic dependency-overlay qualification; qualify
additional Flutter targets/build modes and browser streaming uploads
before making corresponding platform promises. The application fixtures now
provide reproducible macOS and Web transport/resource evidence without
replacing the package/archive consumer gate.
