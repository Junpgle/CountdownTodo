import 'local_image_provider.dart';

Future<String?> persistImagePath(String sourcePath, String subdirectory) async {
  return localImageExists(sourcePath) ? sourcePath : null;
}

Future<void> deletePersistedImagePath(String? path) async {}
