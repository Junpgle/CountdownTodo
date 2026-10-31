import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app_platform.dart';

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
  return Builder(
    builder: (context) {
      final pixelRatio = AppPlatform.isWindows
          ? (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0)
          : 3.0;
      final effectiveCacheWidth =
          cacheWidth ?? _cacheDimension(width, pixelRatio);
      final effectiveCacheHeight =
          cacheHeight ?? _cacheDimension(height, pixelRatio);
      return Image.file(
        File(path),
        fit: fit,
        width: width,
        height: height,
        cacheWidth: effectiveCacheWidth,
        cacheHeight: effectiveCacheHeight,
      );
    },
  );
}

int? _cacheDimension(double? logicalSize, double pixelRatio) {
  if (logicalSize == null || !logicalSize.isFinite || logicalSize <= 0) {
    return null;
  }
  return (logicalSize * pixelRatio).ceil().clamp(1, 4096).toInt();
}
