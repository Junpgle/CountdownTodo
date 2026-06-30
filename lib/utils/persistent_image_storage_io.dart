import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> persistImagePath(String sourcePath, String subdirectory) async {
  final sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) return null;

  final appDir = await getApplicationSupportDirectory();
  final imageDir = Directory('${appDir.path}/$subdirectory');
  if (!await imageDir.exists()) {
    await imageDir.create(recursive: true);
  }

  final fileName =
      '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}';
  final newPath = '${imageDir.path}/$fileName';
  await sourceFile.copy(newPath);
  return newPath;
}

Future<void> deletePersistedImagePath(String? path) async {
  if (path == null || path.isEmpty) return;
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
