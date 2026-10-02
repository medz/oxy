# Transport contracts

The default transport uses `dart:io` on native Dart and Flutter targets, and
Fetch on Web targets. `client.transport.capability` describes features exposed
by that transport's API in the current runtime.

| Feature | Default native | Default Web |
| --- | --- | --- |
| Streaming request bodies | Supported | Depends on the Fetch request-streaming feature probe; buffered when unsupported |
| Streaming response bodies | Supported | Supported through Fetch response streams |
| Upload progress | Supported | Unavailable |
| Download progress | Supported | Supported |
| Proxy configuration input | Unavailable | Unavailable |
| TLS configuration input | Unavailable | Unavailable |

Native proxy and TLS configuration require a custom `Transport`. The default
native transport does not expose `HttpClient` configuration through Oxy's API.
`PlatformCapability.web` describes a runtime with request streaming support;
query the transport instance for the actual runtime result.

## Browser constraints

Browsers control CORS, credentials, forbidden request headers, and access to
response headers. Oxy cannot override those constraints. The `userAgent`
option applies to non-Web transports; browsers control the wire user-agent.
Node uses the Web transport when compiling to JavaScript, but its Fetch runtime
does not impose browser CORS rules.

A successful request-streaming probe establishes a runtime feature, not server
compatibility. For example, [Chrome requires HTTP/2 or HTTP/3 for streaming
requests](https://developer.chrome.com/docs/capabilities/web-apis/fetch-streaming-requests).
Ordinary JSON and other buffered bodies do not require request streaming.
If the probe reports unsupported request streaming, Oxy buffers a raw stream
before sending it; that path requires memory proportional to the body size.

Web redirects use Fetch behavior. An explicit Oxy redirect limit cannot be
enforced by Fetch and produces `PolicyError`. Manual browser redirects may be
opaque and unavailable for status or header inspection.

## Cancellation, timeouts, and ownership

Use `RequestOptions.signal` to cancel a request or a pending response-body read.
Cancellation produces `CancelError` with the caller's reason. A read timeout
limits the wait for each next response chunk and produces
`TimeoutError(phase: TimeoutPhase.read)`. Read and total timeouts abort the
internal request attempt to stop pending transport reads. They do not abort a
caller-supplied signal, and the client remains usable for subsequent requests.

Response streams are one-shot. Consume or cancel the body when finished with a
response; use `Response.buffered()` when it must be read repeatedly.
Await the subscription or iterator's cancellation, including while its next
read is pending. Built-in transports release that read without waiting for
more server bytes. Pausing the consumer suspends the read-idle timer; the
absolute total deadline continues while the subscription is paused.

`Client.close()` is idempotent and closes its owned default transport. Native
close forcibly closes the underlying `HttpClient`. Web close does not close
the browser's connection pool or cancel Fetch requests; use a request signal
for cancellation. A custom transport supplied through `ClientOptions.transport`
is caller-owned, including when shared by clients derived with `withMiddleware`.
Close that transport after all its clients finish using it.

## Qualification scope

CI checks minimum and stable Dart SDKs on VM, Node, and Chrome. Live loopback
HTTP tests cover native and Web GET, buffered Web JSON POST, request-stream
buffering when unsupported, 128KiB response integrity, cancellation after
response headers, and stalled-response read timeouts followed by client reuse.
These complement the policy and middleware tests.

[Application qualification](../tool/qualification/README.md) additionally runs
fresh public-API Flutter macOS and Web consumers and observes actual socket
closure after timeout, caller abort, and response-stream cancellation. Its
version/target scope is explicit. Other Flutter targets/build modes and browser
HTTP/2 streaming uploads remain gates in the [1.0 roadmap](roadmap.md).
Oxy's RFC850 Retry-After normalization works independently of build-hook
overlay ordering, and application probes require correct retry behavior on
the first compilation. This does not fix Patchwork's cold native resolution
gap or qualify upstream parser/cookie contracts; those remain separate gates.
