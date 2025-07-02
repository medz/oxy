import 'adapter_request.dart';

/// Web standards compliant request.
///
/// E.g:
/// ```dart
/// final request = Request("https://example.com");
/// ```
class Request extends AdapterRequest {
  Request(
    this.url, {
    super.method,
    super.headers,
    super.body,
    super.signal,
    super.cache,
    super.integrity,
    super.keepalive,
    super.mode,
    super.priority,
    super.redirect,
    super.referrer,
    super.referrerPolicy,
    super.credentials,
  });

  final String url;

  @override
  Request clone() {
    return Request(
      url,
      body: super.clone(),
      cache: cache,
      method: method,
      headers: headers,
      priority: priority,
      redirect: redirect,
      referrer: referrer,
      referrerPolicy: referrerPolicy,
      signal: signal,
      integrity: integrity,
      keepalive: keepalive,
      mode: mode,
      credentials: credentials,
    );
  }
}
