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
  return Image.network(path, fit: fit, width: width, height: height);
}
