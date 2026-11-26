import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app_platform.dart';

const int _maxExistenceCacheEntries = 256;
const Duration _existsTrueTtl = Duration(seconds: 30);
const Duration _existsFalseTtl = Duration(seconds: 5);
final Map<String, ({bool exists, DateTime expiresAt})> _existenceCache =
    <String, ({bool exists, DateTime expiresAt})>{};

void invalidateLocalImageExistenceCache([String? path]) {
  if (path == null) {
    _existenceCache.clear();
  } else {
    _existenceCache.remove(path);
  }
}

bool localImageExists(String? path) {
  if (path == null || path.isEmpty) return false;
  final now = DateTime.now();
  final cached = _existenceCache.remove(path);
  if (cached != null && now.isBefore(cached.expiresAt)) {
    _existenceCache[path] = cached;
    return cached.exists;
  }
  final exists = File(path).existsSync();
  if (_existenceCache.length >= _maxExistenceCacheEntries) {
    _existenceCache.remove(_existenceCache.keys.first);
  }
  _existenceCache[path] = (
    exists: exists,
    expiresAt: now.add(exists ? _existsTrueTtl : _existsFalseTtl),
  );
  return exists;
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
