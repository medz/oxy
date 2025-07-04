/// Defines the cache policy for HTTP requests.
///
/// This enum controls how the browser's HTTP cache is used when making requests.
/// Each policy determines whether to use cached responses, bypass the cache,
/// or require cached content.
enum RequestCache {
  /// Use the default cache policy.
  ///
  /// The browser uses its normal cache behavior, checking for fresh content
  /// and using cached responses when appropriate.
  defaults,

  /// Bypass the cache completely and don't store the response.
  ///
  /// Forces the browser to fetch from the network and not store the response
  /// in the cache. Equivalent to a completely fresh request.
  noStore,

  /// Force a reload, bypassing any cached response.
  ///
  /// The browser will always fetch from the network, ignoring any cached
  /// version, but will store the new response in the cache.
  reload,

  /// Bypass the cache for the request but allow cached responses.
  ///
  /// The browser will fetch from the network but may use a cached response
  /// if the server indicates it's still valid (e.g., with 304 Not Modified).
  noCache,

  /// Only use cached responses, never fetch from network.
  ///
  /// The browser will only use cached responses and will not make a network
  /// request. If no cached response exists, the request will fail.
  forceCache,

  /// Only use cached responses if they exist.
  ///
  /// Similar to [forceCache], but specifically indicates that the request
  /// should only succeed if a cached response is available.
  onlyIfCached;

  /// Returns the [value] of the request cache policy.
  ///
  /// > [!NOTE]
  /// > If the [value] is not recognized, it returns [defaults].
  static RequestCache lookup(String value) {
    return switch (value) {
      'default' => defaults,
      'no-store' => noStore,
      'reload' => reload,
      'no-cache' => noCache,
      'force-cache' => forceCache,
      'only-if-cached' => onlyIfCached,
      _ => defaults,
    };
  }

  @override
  String toString() {
    return switch (this) {
      defaults => 'default',
      noStore => 'no-store',
      reload => 'reload',
      noCache => 'no-cache',
      forceCache => 'force-cache',
      onlyIfCached => 'only-if-cached',
    };
  }
}

/// Defines the credentials policy for HTTP requests.
///
/// This enum controls whether user credentials (cookies, authorization headers,
/// or TLS client certificates) are sent with requests and how they're handled
/// in responses.
enum RequestCredentials {
  /// Never send credentials in the request or include credentials in the response.
  ///
  /// No cookies, authorization headers, or TLS client certificates will be
  /// sent with the request, regardless of the request's origin.
  omit,

  /// Only send and include credentials for same-origin requests. This is the default.
  ///
  /// Credentials are only sent when the request is to the same origin as the
  /// calling script. This is the most secure default behavior.
  sameOrigin,

  /// Always include credentials, even for cross-origin requests.
  ///
  /// Credentials are sent with all requests, including cross-origin requests.
  /// The server must explicitly allow credentials in CORS responses.
  include;

  /// Returns the [RequestCredentials] enum value for the given string.
  ///
  /// If the [value] is not recognized, returns [sameOrigin] as the default.
  ///
  /// Supported values:
  /// - `'omit'` → [omit]
  /// - `'same-origin'` → [sameOrigin]
  /// - `'include'` → [include]
  static RequestCredentials lookup(String value) {
    return switch (value) {
      'omit' => omit,
      'same-origin' => sameOrigin,
      'include' => include,
      _ => sameOrigin,
    };
  }

  @override
  String toString() {
    return switch (this) {
      omit => 'omit',
      sameOrigin => 'same-origin',
      include => 'include',
    };
  }
}

/// Defines the mode for HTTP requests.
///
/// This enum controls how the request interacts with CORS (Cross-Origin Resource Sharing)
/// and determines what types of responses are allowed.
enum RequestMode {
  /// Enable CORS for cross-origin requests.
  ///
  /// The request will follow CORS protocol for cross-origin requests,
  /// allowing access to cross-origin resources when properly configured.
  cors,

  /// Disable CORS, preventing access to cross-origin response details.
  ///
  /// Cross-origin requests are allowed but the response is opaque,
  /// meaning you cannot read the response body, headers, or status.
  noCors,

  /// Only allow same-origin requests.
  ///
  /// The request will fail if made to a different origin than the
  /// requesting page. Only same-origin requests are permitted.
  sameOrigin,

  /// Navigation mode for page navigation requests.
  ///
  /// Used for navigation requests (like clicking a link or form submission).
  /// This mode is typically used internally by the browser.
  navigate;

  /// Returns the [RequestMode] enum value for the given string.
  ///
  /// If the [value] is not recognized, returns [sameOrigin] as the default.
  ///
  /// Supported values:
  /// - `'cors'` → [cors]
  /// - `'no-cors'` → [noCors]
  /// - `'same-origin'` → [sameOrigin]
  /// - `'navigate'` → [navigate]
  static RequestMode lookup(String value) {
    return switch (value) {
      'cors' => cors,
      'no-cors' => noCors,
      'same-origin' => sameOrigin,
      'navigate' => navigate,
      _ => sameOrigin,
    };
  }

  @override
  String toString() {
    return switch (this) {
      cors => 'cors',
      noCors => 'no-cors',
      sameOrigin => 'same-origin',
      navigate => 'navigate',
    };
  }
}

/// Defines the priority level for HTTP requests.
///
/// This enum allows you to indicate the relative importance of a request,
/// which can help browsers optimize resource loading and network usage.
enum RequestPriority {
  /// Automatic priority determination.
  ///
  /// Let the browser determine the appropriate priority based on the
  /// request type and context. This is the default behavior.
  auto,

  /// Low priority request.
  ///
  /// Indicates this request has lower priority and can be deferred
  /// in favor of higher priority requests.
  low,

  /// High priority request.
  ///
  /// Indicates this request should be prioritized over lower priority
  /// requests when competing for network resources.
  high;

  /// Returns the [RequestPriority] enum value for the given string.
  ///
  /// If the [value] is not recognized, returns [auto] as the default.
  ///
  /// Supported values:
  /// - `'auto'` → [auto]
  /// - `'low'` → [low]
  /// - `'high'` → [high]
  static RequestPriority lookup(String value) {
    return switch (value) {
      'auto' => auto,
      'low' => low,
      'high' => high,

      _ => auto,
    };
  }

  @override
  String toString() => name;
}

/// Defines how HTTP redirects should be handled.
///
/// This enum controls the behavior when a server responds with a redirect
/// status code (3xx). Different policies provide different levels of control
/// over the redirect process.
enum RequestRedirect {
  /// Automatically follow redirects.
  ///
  /// The browser will automatically follow redirect responses and return
  /// the final response. This is the typical behavior for most requests.
  follow,

  /// Treat redirects as errors.
  ///
  /// Any redirect response will be treated as a network error, causing
  /// the request to fail instead of following the redirect.
  error,

  /// Handle redirects manually.
  ///
  /// Redirect responses are returned as-is without automatic following,
  /// allowing the application to handle redirects programmatically.
  manual;

  /// Returns the [RequestRedirect] enum value for the given string.
  ///
  /// If the [value] is not recognized, returns [follow] as the default.
  ///
  /// Supported values:
  /// - `'follow'` → [follow]
  /// - `'error'` → [error]
  /// - `'manual'` → [manual]
  static RequestRedirect lookup(String value) {
    return switch (value) {
      'follow' => follow,
      'error' => error,
      'manual' => manual,

      _ => follow,
    };
  }

  @override
  String toString() => name;
}

/// Defines the referrer policy for HTTP requests.
///
/// This enum controls what referrer information is sent with requests,
/// balancing between functionality and privacy. The referrer header indicates
/// which page initiated the request.
enum ReferrerPolicy {
  empty,

  /// Never send referrer information.
  ///
  /// The Referer header will be omitted entirely from all requests.
  /// This provides maximum privacy but may break some functionality.
  noReferrer,

  /// Send full referrer for HTTPS→HTTPS, no referrer for HTTPS→HTTP.
  ///
  /// Sends the full URL as referrer for same-protocol requests, but
  /// omits referrer when downgrading from HTTPS to HTTP.
  noReferrerWhenDowngrade,

  /// Send only the origin (scheme, host, port) as referrer.
  ///
  /// Only the origin part of the URL is sent, without path or query parameters.
  /// Provides a balance between functionality and privacy.
  origin,

  /// Send full referrer for same-origin, origin-only for cross-origin.
  ///
  /// Sends the complete URL for same-origin requests, but only the origin
  /// for cross-origin requests.
  originWhenCrossOrigin,

  /// Send referrer only for same-origin requests.
  ///
  /// The full URL is sent as referrer for same-origin requests, but
  /// no referrer is sent for cross-origin requests.
  sameOrigin,

  /// Send origin when protocol security level stays same or improves.
  ///
  /// Sends the origin when the security level is maintained or improved
  /// (HTTP→HTTP, HTTP→HTTPS, HTTPS→HTTPS), but not when downgrading (HTTPS→HTTP).
  strictOrigin,

  /// Combines strict-origin with origin-when-cross-origin behavior.
  ///
  /// Sends full URL for same-origin, origin for cross-origin when security
  /// level is maintained, and no referrer when downgrading protocols.
  strictOriginWhenCrossOrigin,

  /// Always send the full URL as referrer.
  ///
  /// The complete URL is always sent as referrer, regardless of security
  /// implications. This is the least private option.
  unsafeUrl;

  /// Returns the [ReferrerPolicy] enum value for the given string.
  ///
  /// If the [value] is not recognized, returns `null`.
  ///
  /// Supported values:
  /// - `'no-referrer'` → [noReferrer]
  /// - `'no-referrer-when-downgrade'` → [noReferrerWhenDowngrade]
  /// - `'origin'` → [origin]
  /// - `'origin-when-cross-origin'` → [originWhenCrossOrigin]
  /// - `'same-origin'` → [sameOrigin]
  /// - `'strict-origin'` → [strictOrigin]
  /// - `'strict-origin-when-cross-origin'` → [strictOriginWhenCrossOrigin]
  /// - `'unsafe-url'` → [unsafeUrl]
  static ReferrerPolicy lookup(String value) {
    return switch (value) {
      'no-referrer' => noReferrer,
      'no-referrer-when-downgrade' => noReferrerWhenDowngrade,
      'origin' => origin,
      'origin-when-cross-origin' => originWhenCrossOrigin,
      'same-origin' => sameOrigin,
      'strict-origin' => strictOrigin,
      'strict-origin-when-cross-origin' => strictOriginWhenCrossOrigin,
      'unsafe-url' => unsafeUrl,
      _ => empty,
    };
  }

  @override
  String toString() {
    return switch (this) {
      noReferrer => 'no-referrer',
      noReferrerWhenDowngrade => 'no-referrer-when-downgrade',
      origin => 'origin',
      originWhenCrossOrigin => 'origin-when-cross-origin',
      sameOrigin => 'same-origin',
      strictOrigin => 'strict-origin',
      strictOriginWhenCrossOrigin => 'strict-origin-when-cross-origin',
      unsafeUrl => 'unsafe-url',
      empty => '',
    };
  }
}
