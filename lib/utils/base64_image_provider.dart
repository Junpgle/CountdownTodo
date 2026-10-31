import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Uses encoded content as the image-cache key, decoding bytes only on a miss.
/// Rebuilding a widget with the same photo therefore reuses its decoded image.
@immutable
class Base64ImageProvider extends ImageProvider<Base64ImageProvider> {
  const Base64ImageProvider(this.encoded);

  final String encoded;

  @override
  Future<Base64ImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<Base64ImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    Base64ImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: 'Base64Image',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      base64Decode(encoded),
    );
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is Base64ImageProvider && other.encoded == encoded;

  @override
  int get hashCode => Object.hash(Base64ImageProvider, encoded);
}
