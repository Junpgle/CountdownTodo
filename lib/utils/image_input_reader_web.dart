import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'image_input_data.dart';

Future<ImageInputData> readImageInput(String imagePath) async {
  if (imagePath.startsWith('data:')) {
    return _readDataUrl(imagePath);
  }

  final uri = Uri.tryParse(imagePath);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'blob')) {
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('图片读取失败: HTTP ${response.statusCode}');
    }
    return ImageInputData(
      bytes: response.bodyBytes,
      mimeType: response.headers['content-type']?.split(';').first ??
          _guessMimeType(imagePath),
      displayName: imagePath,
    );
  }

  throw UnsupportedError('Web 端无法读取本地图片路径，请使用浏览器文件选择器提供图片内容');
}

ImageInputData _readDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  if (comma <= 0) throw const FormatException('无效的 data URL');
  final meta = dataUrl.substring(5, comma);
  final payload = dataUrl.substring(comma + 1);
  final mimeType =
      meta.split(';').first.isEmpty ? 'image/jpeg' : meta.split(';').first;
  final bytes = meta.contains(';base64')
      ? base64Decode(payload)
      : Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
  return ImageInputData(
    bytes: bytes,
    mimeType: mimeType,
    displayName: 'browser-image',
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
