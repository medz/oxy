import 'abort.dart';

enum RedirectPolicy { follow, manual, error }

class FetchOptions {
  const FetchOptions({
    this.signal,
    this.redirect = RedirectPolicy.follow,
    this.maxRedirects = 5,
    this.keepAlive = false,
    this.timeout,
  }) : assert(maxRedirects >= 0, 'maxRedirects must be >= 0');

  final AbortSignal? signal;
  final RedirectPolicy redirect;
  final int maxRedirects;
  final bool keepAlive;
  final Duration? timeout;

  FetchOptions copyWith({
    AbortSignal? signal,
    RedirectPolicy? redirect,
    int? maxRedirects,
    bool? keepAlive,
    Duration? timeout,
  }) {
    return FetchOptions(
      signal: signal ?? this.signal,
      redirect: redirect ?? this.redirect,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      keepAlive: keepAlive ?? this.keepAlive,
      timeout: timeout ?? this.timeout,
    );
  }
}
