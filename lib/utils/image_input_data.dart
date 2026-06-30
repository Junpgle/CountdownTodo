import 'dart:typed_data';

class ImageInputData {
  final Uint8List bytes;
  final String mimeType;
  final String displayName;

  const ImageInputData({
    required this.bytes,
    required this.mimeType,
    required this.displayName,
  });

  int get length => bytes.lengthInBytes;
}
