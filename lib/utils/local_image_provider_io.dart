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
}) {
  if (!AppPlatform.isWindows || (width == null && height == null)) {
    return Image.file(File(path), fit: fit, width: width, height: height);
  }
  return Builder(
    builder: (context) {
      final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      final cacheWidth = _cacheDimension(width, pixelRatio);
      final cacheHeight = _cacheDimension(height, pixelRatio);
      final provider = FileImage(File(path));
      final ImageProvider<Object> resizedProvider =
          cacheWidth == null && cacheHeight == null
          ? provider
          : ResizeImage(
              provider,
              width: cacheWidth,
              height: cacheHeight,
              policy: ResizeImagePolicy.fit,
            );
      return Image(
        image: resizedProvider,
        fit: fit,
        width: width,
        height: height,
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
