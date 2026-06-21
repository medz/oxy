import '../core/errors.dart';
import '../core/request.dart';
import '../core/response.dart';
import '../pipeline/context.dart';
import '../pipeline/internal_attributes.dart';
import '../policies.dart';
import 'response_policies.dart';

typedef RedirectHandler =
    Future<Response> Function(Request request, Context context);

bool usesClientRedirects(Context context) {
  return context.redirectPolicy.mode == RedirectMode.follow &&
      context.capability.name != 'web';
}

Future<Response> runRedirects(
  Request request,
  Context context,
  RedirectHandler next, {
  Response? firstResponse,
}) async {
  var current = request;
  var redirected = false;
  var response = firstResponse;
  for (var redirects = 0; ; redirects++) {
    response ??= await next(current, _allowRedirectStatus(context));
    if (!isRedirectStatus(response.status)) {
      return redirected ? response.copyWith(redirected: true) : response;
    }

    final location = response.headers.get('location');
    if (location == null || location.trim().isEmpty) {
      throw StatusError(
        response,
        request: current,
        message: 'Redirect response is missing a Location header.',
      );
    }
    if (redirects >= context.redirectPolicy.maxRedirects) {
      throw StatusError(
        response,
        request: current,
        message: 'Too many redirects.',
      );
    }
    if (!_redirectChangesToGet(response.status, current.method) &&
        current.body?.replayable == false) {
      await response.drain(maxBytes: null);
      throw StatusError(
        response,
        request: current,
        message: 'Redirect requires a replayable request body.',
      );
    }

    await response.drain(maxBytes: null);
    try {
      current = _redirectRequest(current, response, location);
    } on FormatException catch (_, trace) {
      throw StatusError(
        response,
        request: current,
        message: 'Redirect response has an invalid Location header.',
        trace: trace,
      );
    }
    redirected = true;
    response = null;
  }
}

Request sanitizeRedirectHeaders(Request request) {
  if (request.attributes.get(redirectCrossOriginAttribute) != true) {
    return request;
  }

  final headers = request.headers.copy()
    ..delete('authorization')
    ..delete('proxy-authorization');
  if (request.attributes.get(cookieHeaderManagedAttribute) != true) {
    headers.delete('cookie');
  }
  return request.copyWith(headers: headers);
}

Context _allowRedirectStatus(Context context) {
  return context.copyWith(
    statusPolicy: StatusPolicy(
      accept: (response) {
        return isRedirectStatus(response.status) ||
            context.statusPolicy.accepts(response);
      },
    ),
  );
}

Request _redirectRequest(Request request, Response response, String location) {
  final base = response.url.hasScheme ? response.url : request.uri;
  final nextUri = base.resolve(location);
  final sameOrigin = _sameOrigin(request.uri, nextUri);
  final nextHeaders = request.headers.copy();
  var nextAttributes = request.attributes;
  if (!sameOrigin) {
    nextHeaders.delete('authorization');
    nextHeaders.delete('cookie');
    nextHeaders.delete('proxy-authorization');
    nextAttributes = nextAttributes
        .remove(cookieHeaderManagedAttribute)
        .set(redirectCrossOriginAttribute, true);
  }

  var method = request.method;
  var clearBody = false;
  if (_redirectChangesToGet(response.status, method)) {
    method = 'GET';
    clearBody = true;
    nextHeaders.delete('content-length');
    nextHeaders.delete('content-type');
  }

  return request.copyWith(
    method: method,
    uri: nextUri,
    headers: nextHeaders,
    clearBody: clearBody,
    attributes: nextAttributes,
  );
}

bool _redirectChangesToGet(int status, String method) {
  final upper = method.toUpperCase();
  if (status == 303 && upper != 'GET' && upper != 'HEAD') {
    return true;
  }
  return (status == 301 || status == 302) && upper == 'POST';
}

bool _sameOrigin(Uri a, Uri b) {
  return a.scheme == b.scheme && a.host == b.host && _portOf(a) == _portOf(b);
}

int _portOf(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return switch (uri.scheme) {
    'http' => 80,
    'https' => 443,
    _ => 0,
  };
}
