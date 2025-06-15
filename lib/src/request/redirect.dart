enum RequestRedirect {
  error,
  follow,
  manual;

  static RequestRedirect parse(String value) {
    return switch (value) {
      'error' => error,
      'follow' => follow,
      'manual' => manual,
      _ => follow,
    };
  }
}
