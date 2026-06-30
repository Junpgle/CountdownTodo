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
}) {
  return Image.file(
    File(path),
    fit: fit,
    width: width,
    height: height,
  );
}
