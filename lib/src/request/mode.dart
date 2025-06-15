enum RequestMode {
  cors('cors'),
  noCors("no-cors"),
  sameOrigin("same-origin"),
  navigate("navigate");

  final String value;
  const RequestMode(this.value);
  static RequestMode parse(String value) {
    return switch (value) {
      'cors' => cors,
      'no-cors' => noCors,
      'same-origin' => sameOrigin,
      'navigate' => navigate,
      _ => cors,
    };
  }
}
