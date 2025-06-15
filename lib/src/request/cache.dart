enum RequestCache {
  default_("default"),
  noStore("no-store"),
  reload("reload"),
  noCache("no-cache"),
  forceCache("force-cache"),
  onlyIfCached("only-if-cached");

  final String value;
  const RequestCache(this.value);

  static RequestCache parse(String value) {
    return switch (value) {
      'default' => default_,
      'no-store' => noStore,
      'reload' => reload,
      'no-cache' => noCache,
      'force-cache' => forceCache,
      'only-if-cached' => onlyIfCached,
      _ => default_,
    };
  }
}
