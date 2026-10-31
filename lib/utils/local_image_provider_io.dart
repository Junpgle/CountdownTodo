import 'dart:io';

import 'package:flutter/widgets.dart';

bool localImageExists(String? path) {
  if (path == null || path.isEmpty) return false;
  return File(path).existsSync();
}

ImageProvider<Object>? localImageProvider(String? path) {
  if (!localImageExists(path)) return null;
  return FileImage(File(path!));
}

Widget localImageWidget(
  String path, {
  BoxFit? fit,
  double? width,
  double? height,
  int? cacheWidth,
  int? cacheHeight,
}) {
  int? effectiveCacheWidth = cacheWidth;
  int? effectiveCacheHeight = cacheHeight;
  if (effectiveCacheWidth == null && effectiveCacheHeight == null) {
    if (width != null && width.isFinite && width > 0) {
      effectiveCacheWidth = (width * 3).round().clamp(1, 4096);
    }
    if (height != null && height.isFinite && height > 0) {
      effectiveCacheHeight = (height * 3).round().clamp(1, 4096);
    }
  }
  return Image.file(
    File(path),
    fit: fit,
    width: width,
    height: height,
    cacheWidth: effectiveCacheWidth,
    cacheHeight: effectiveCacheHeight,
  );
}
