import '../url_search_params/url_search_params.dart' show URLSearchParams;

final class Store {
  Store(this.uri, [URLSearchParams? searchParams])
    : searchParams = searchParams ?? URLSearchParams.parse(uri.query);

  Uri uri;
  URLSearchParams searchParams;

  @override
  String toString() {
    final searchParams = this.searchParams.stringify();
    if (uri.query == searchParams) return uri.toString();
    return uri.replace(query: searchParams).toString();
  }
}

extension type URL._(Store _) {
  factory URL(String url, [String? base]) {
    final uri = switch (base) {
      String base => Uri.parse(base).resolve(url),
      _ => Uri.base.resolve(url),
    };

    return URL._(Store(uri));
  }

  static URL? parse(String url, [String? base]) {
    final resolvedBase = base != null ? Uri.tryParse(base) : Uri.base;
    if (base != null && resolvedBase == null) return null;

    final resolvedUrl = Uri.tryParse(url);
    if (resolvedUrl == null) return null;

    try {
      final uri = resolvedBase?.resolveUri(resolvedUrl) ?? resolvedUrl;
      return URL._(Store(uri));
    } catch (_) {
      return null;
    }
  }

  static bool canParse(String url, [String? base]) {
    final resolvedBase = base != null ? Uri.tryParse(base) : null;
    final resolvedUrl = Uri.tryParse(url);
    if (resolvedUrl == null || (base != null && resolvedBase == null)) {
      return false;
    }

    try {
      if (base != null && resolvedBase?.resolveUri(resolvedUrl) == null) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  String get origin => _.uri.origin;
  URLSearchParams get searchParams => _.searchParams;

  String get hash {
    final hash = _.uri.fragment;
    if (hash.isEmpty || hash.startsWith('#')) return hash;
    return '#$hash';
  }

  set hash(String value) {
    if (value.startsWith('#')) value = value.substring(1);
    _.uri = switch (value) {
      String(isEmpty: true) => _.uri.removeFragment(),
      String value => _.uri.replace(fragment: value),
    };
  }

  String get hostname => _.uri.host;
  set hostname(String value) => _.uri = _.uri.replace(host: value);

  String get host {
    final Uri(:hasPort, :host, :port) = _.uri;
    if (hasPort || port != 0) return '$host:$port';
    return host;
  }

  set host(String value) {
    final [...parts, port] = value.split(":");
    if (parts.isEmpty) {
      _.uri = Uri(
        scheme: _.uri.hasScheme ? _.uri.scheme : null,
        host: port,
        path: pathname,
        userInfo: _.uri.userInfo.isNotEmpty ? _.uri.userInfo : null,
        fragment: _.uri.hasFragment ? _.uri.fragment : null,
      );
      return;
    }

    _.uri = _.uri.replace(host: parts.join(":"), port: int.parse(port));
  }

  String get href => _.toString();
  set href(String value) => _.uri = _.uri.resolve(value);

  String get pathname => _.uri.path;
  set pathname(String value) => _.uri = _.uri.replace(path: value);

  int get port => _.uri.port;
  set port(int value) {
    if (value == 0) {
      _.uri = Uri(
        scheme: _.uri.hasScheme ? _.uri.scheme : null,
        host: hostname,
        port: _.uri.hasPort ? port : null,
        path: pathname,
        userInfo: _.uri.userInfo.isNotEmpty ? _.uri.userInfo : null,
        fragment: _.uri.hasFragment ? _.uri.fragment : null,
      );
      return;
    }

    _.uri = _.uri.replace(port: value);
  }

  String get protocol => '${_.uri.scheme}:';
  set protocol(String value) {
    if (value.endsWith(':')) value = value.substring(0, value.length - 1);
    _.uri = _.uri.replace(scheme: value);
  }

  String get search {
    final search = searchParams.stringify();
    if (search.isEmpty || search.startsWith('?')) return search;
    return '?$search';
  }

  set search(String value) => _.searchParams = URLSearchParams.parse(value);

  String get username {
    final [username] = _.uri.userInfo.split(':');
    return username;
  }

  set username(String value) {
    _.uri = _.uri.replace(userInfo: '$username:$password');
  }

  String get password {
    final [_, ...password] = _.uri.userInfo.split(':');
    if (password.isEmpty) return '';
    return password.join(':');
  }

  set password(String value) {
    _.uri = _.uri.replace(userInfo: '$username:$password');
  }
}
