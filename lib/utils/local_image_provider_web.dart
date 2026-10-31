import 'package:flutter/widgets.dart';

import '../services/github_resource_service.dart';

bool _isBrowserImagePath(String? path) {
  if (path == null || path.isEmpty) return false;
  final uri = Uri.tryParse(path);
  return uri != null &&
      (uri.scheme == 'http' ||
          uri.scheme == 'https' ||
          uri.scheme == 'blob' ||
          uri.scheme == 'data');
}

bool localImageExists(String? path) => _isBrowserImagePath(path);

ImageProvider<Object>? localImageProvider(String? path) {
  if (!_isBrowserImagePath(path)) return null;
  return NetworkImage(path!);
}

Widget localImageWidget(
  String path, {
  BoxFit? fit,
  double? width,
  double? height,
  int? cacheWidth,
  int? cacheHeight,
}) {
  if (!_isBrowserImagePath(path)) {
    return const SizedBox.shrink();
  }
  final uri = Uri.tryParse(path);
  if (uri != null && GitHubResourceService.isGitHubUri(uri)) {
    return GitHubResourceImage(
      url: path,
      fit: fit,
      width: width,
      height: height,
    );
  }
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
  return Image.network(
    path,
    fit: fit,
    width: width,
    height: height,
    cacheWidth: effectiveCacheWidth,
    cacheHeight: effectiveCacheHeight,
  );
}
