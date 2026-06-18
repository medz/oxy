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

  final String name;
  final bool uploadProgress;
  final bool downloadProgress;
  final bool streamingRequestBody;
  final bool streamingResponseBody;
  final bool proxyConfiguration;
  final bool tlsConfiguration;

  static const PlatformCapability native = PlatformCapability(
    name: 'native',
    uploadProgress: true,
    downloadProgress: true,
    streamingRequestBody: true,
    streamingResponseBody: true,
    proxyConfiguration: true,
    tlsConfiguration: true,
  );

  static const PlatformCapability web = PlatformCapability(
    name: 'web',
    uploadProgress: false,
    downloadProgress: true,
    streamingRequestBody: true,
    streamingResponseBody: true,
    proxyConfiguration: false,
    tlsConfiguration: false,
  );

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
