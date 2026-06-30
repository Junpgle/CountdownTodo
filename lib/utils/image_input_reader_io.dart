import 'dart:io';

import 'image_input_data.dart';

Future<ImageInputData> readImageInput(String imagePath) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    throw Exception('图片文件不存在: $imagePath');
  }
  final bytes = await file.readAsBytes();
  return ImageInputData(
    bytes: bytes,
    mimeType: _guessMimeType(imagePath),
    displayName: imagePath,
  );
}

String _guessMimeType(String path) {
  switch (path.split('.').last.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}
