import '../core/attributes.dart';
import '../core/body.dart';
import '../core/headers.dart';
import '../core/request.dart';
import '../options.dart';
import '../pipeline/context.dart';
import '../pipeline/middleware.dart';
import '../transport/capability.dart';

final class ResolvedRequest {
  const ResolvedRequest(this.request, this.context);

  final Request request;
  final Context context;
}

ResolvedRequest resolveClientRequest(
  Request request,
  RequestOptions? sendOptions, {
  required ClientOptions clientOptions,
  required PlatformCapability capability,
}) {
  final incoming = _mergeRequestOptions(request.options, sendOptions);
  final timeoutPolicy = incoming.timeoutPolicy ?? clientOptions.timeoutPolicy;
  final retryPolicy = incoming.retryPolicy ?? clientOptions.retryPolicy;
  final redirectPolicy =
      incoming.redirectPolicy ?? clientOptions.redirectPolicy;
  final statusPolicy = incoming.statusPolicy ?? clientOptions.statusPolicy;

  final attributes = _mergeAttributes(
    clientOptions.attributes,
    request.attributes,
    incoming.attributes,
  );

  final context = Context(
    clientOptions: clientOptions,
    requestOptions: incoming,
    timeoutPolicy: timeoutPolicy,
    retryPolicy: retryPolicy,
    redirectPolicy: redirectPolicy,
    statusPolicy: statusPolicy,
    capability: capability,
    attributes: attributes,
    createdAt: DateTime.now().toUtc(),
    attempt: 0,
    signal: incoming.signal,
    onEvent: clientOptions.onEvent,
  );

  final resolvedUrl = _resolveUrl(
    _mergeQuery(request.uri, incoming.query),
    clientOptions.baseUrl,
  );
  final headers = Headers(clientOptions.defaultHeaders);
  _overrideHeaders(headers, request.headers);
  if (incoming.headers != null) {
    _overrideHeaders(headers, Headers(incoming.headers));
  }
  if (capability.name != 'web' &&
      clientOptions.userAgent.isNotEmpty &&
      !headers.has('user-agent')) {
    headers.set('user-agent', clientOptions.userAgent);
  }

  final body = request.body;
  if (body?.contentType != null && !headers.has('content-type')) {
    headers.set('content-type', body!.contentType!);
  }
  if (capability.name != 'web' &&
      body?.contentLength != null &&
      !headers.has('content-length')) {
    headers.set('content-length', body!.contentLength!.toString());
  }

  final prepared = request.copyWith(
    method: request.method.toUpperCase(),
    uri: resolvedUrl,
    headers: headers,
    options: incoming,
    attributes: attributes,
  );

  return ResolvedRequest(prepared, context);
}

Body? resolveRequestBody({
  required Object? body,
  required Object? json,
  required Object jsonOmitted,
}) {
  if (body != null && !identical(json, jsonOmitted)) {
    throw ArgumentError('Use either body or json, not both.');
  }
  if (!identical(json, jsonOmitted)) {
    return Body.fromJson(json);
  }
  return Body.from(body);
}

void _overrideHeaders(Headers target, Headers source) {
  final names = <String>{};
  for (final entry in source.entries()) {
    final name = entry.key;
    if (names.add(name)) {
      target.delete(name);
    }
    target.append(name, entry.value);
  }
}

RequestOptions _mergeRequestOptions(
  RequestOptions requestOptions,
  RequestOptions? sendOptions,
) {
  if (sendOptions == null) {
    return requestOptions;
  }

  return requestOptions.copyWith(
    headers: sendOptions.headers,
    query: sendOptions.query,
    timeoutPolicy: sendOptions.timeoutPolicy,
    retryPolicy: sendOptions.retryPolicy,
    redirectPolicy: sendOptions.redirectPolicy,
    statusPolicy: sendOptions.statusPolicy,
    middleware: <Middleware>[
      ...requestOptions.middleware,
      ...sendOptions.middleware,
    ],
    networkMiddleware: <Middleware>[
      ...requestOptions.networkMiddleware,
      ...sendOptions.networkMiddleware,
    ],
    hooks: requestOptions.hooks?.merge(sendOptions.hooks) ?? sendOptions.hooks,
    signal: sendOptions.signal,
    onSendProgress: sendOptions.onSendProgress,
    onReceiveProgress: sendOptions.onReceiveProgress,
    attributes: _mergeAttributes(
      requestOptions.attributes,
      sendOptions.attributes,
    ),
  );
}

Attributes _mergeAttributes(
  Attributes first,
  Attributes second, [
  Attributes third = const Attributes(),
]) {
  if (second.isEmpty && third.isEmpty) {
    return first;
  }

  final merged = <AttributeKey<Object>, Object>{};
  if (first.isNotEmpty) {
    merged.addAll(first.toMap());
  }
  if (second.isNotEmpty) {
    merged.addAll(second.toMap());
  }
  if (third.isNotEmpty) {
    merged.addAll(third.toMap());
  }
  return Attributes(merged);
}

Uri _resolveUrl(Uri url, Uri? baseUrl) {
  if (url.hasScheme) {
    return url;
  }
  if (baseUrl == null) {
    throw ArgumentError.value(
      url.toString(),
      'url',
      'Relative URLs require ClientOptions(baseUrl: ...).',
    );
  }
  return baseUrl.resolveUri(url);
}

Uri _mergeQuery(Uri uri, QueryMap? query) {
  if (query == null || query.isEmpty) {
    return uri;
  }

  final merged = <String, List<String>>{
    for (final entry in uri.queryParametersAll.entries)
      entry.key: List<String>.from(entry.value),
  };

  for (final entry in query.entries) {
    final value = entry.value;
    if (value == null) {
      continue;
    }
    if (value is Iterable && value is! String) {
      merged[entry.key] = value.map((item) => item.toString()).toList();
    } else {
      merged[entry.key] = <String>[value.toString()];
    }
  }

  final parts = <String>[];
  for (final entry in merged.entries) {
    for (final value in entry.value) {
      parts.add(
        '${Uri.encodeQueryComponent(entry.key)}='
        '${Uri.encodeQueryComponent(value)}',
      );
    }
  }
  return uri.replace(query: parts.join('&'));
}
