import 'package:ht/ht.dart';

import 'errors.dart';
import 'options.dart';

extension OxyResponseDecodeExtension on Response {
  Future<T> decode<T>({Decoder<T>? decoder}) async {
    Object? payload;
    try {
      payload = await json<Object?>();
    } catch (error, trace) {
      throw OxyDecodeException(
        'Failed to decode response body as JSON',
        cause: error,
        trace: trace,
      );
    }

    try {
      return decoder != null ? decoder(payload) : payload as T;
    } catch (error, trace) {
      throw OxyDecodeException(
        'Failed to map decoded payload to `$T`',
        cause: error,
        trace: trace,
      );
    }
  }
}
