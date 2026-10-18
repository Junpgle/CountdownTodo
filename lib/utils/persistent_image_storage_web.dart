import 'dart:typed_data';

import 'local_image_provider.dart';

Future<String?> persistImagePath(String sourcePath, String subdirectory) async {
  return localImageExists(sourcePath) ? sourcePath : null;
}

Future<String?> persistImageBytes(
  Uint8List bytes,
  String subdirectory,
  String fileName,
) async =>
    null;

Future<void> deletePersistedImagePath(String? path) async {}
