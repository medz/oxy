/// Feature flags exposed by a transport implementation.
///
/// Middleware can use these flags to avoid relying on behavior that is not
/// available on a platform, such as browser cookie management or proxy config.
final class PlatformCapability {
  const PlatformCapability({
    required this.name,
    required this.uploadProgress,
    required this.downloadProgress,
    required this.streamingRequestBody,
    required this.streamingResponseBody,
    required this.proxyConfiguration,
    required this.tlsConfiguration,
  });

  /// Stable transport name such as `native`, `web`, or `test`.
  final String name;

  /// Whether upload progress can be reported.
  final bool uploadProgress;

  /// Whether download progress can be reported.
  final bool downloadProgress;

  /// Whether request bodies may be streamed.
  final bool streamingRequestBody;

  /// Whether response bodies may be streamed.
  final bool streamingResponseBody;

  /// Whether proxy configuration is available.
  final bool proxyConfiguration;

  /// Whether TLS configuration is available.
  final bool tlsConfiguration;

  /// Capability set for the default native transport.
  static const PlatformCapability native = PlatformCapability(
    name: 'native',
    uploadProgress: true,
    downloadProgress: true,
    streamingRequestBody: true,
    streamingResponseBody: true,
    proxyConfiguration: true,
    tlsConfiguration: true,
  );

  /// Capability set for the default Web transport.
  static const PlatformCapability web = PlatformCapability(
    name: 'web',
    uploadProgress: false,
    downloadProgress: true,
    streamingRequestBody: true,
    streamingResponseBody: true,
    proxyConfiguration: false,
    tlsConfiguration: false,
  );

  /// Capability set for `MockTransport`.
  static const PlatformCapability test = PlatformCapability(
    name: 'test',
    uploadProgress: true,
    downloadProgress: true,
    streamingRequestBody: true,
    streamingResponseBody: true,
    proxyConfiguration: false,
    tlsConfiguration: false,
  );
}
