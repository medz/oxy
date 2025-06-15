enum RequestCredentials {
  omit("omit"),
  sameOrigin("same-origin"),
  include("include");

  final String value;
  const RequestCredentials(this.value);

  static RequestCredentials parse(String value) {
    return switch (value) {
      "omit" => omit,
      'same-origin' => sameOrigin,
      'include' => include,
      _ => omit,
    };
  }
}
