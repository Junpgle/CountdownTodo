import 'package:crypto/crypto.dart';

/// Captures the single [Digest] emitted by a chunked hash conversion.
class SingleDigestSink implements Sink<Digest> {
  Digest? value;

  Digest get requireValue => value!;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
