import 'dart:io';
import 'dart:typed_data';

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

Future<String?> persistImageBytes(
  Uint8List bytes,
  String subdirectory,
  String fileName,
) async {
  if (bytes.isEmpty) return null;

  final appDir = await getApplicationSupportDirectory();
  final imageDir = Directory('${appDir.path}/$subdirectory');
  if (!await imageDir.exists()) {
    await imageDir.create(recursive: true);
  }

  final safeName = p
      .basename(fileName)
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final uniqueName = '${DateTime.now().microsecondsSinceEpoch}_$safeName';
  final file = File(p.join(imageDir.path, uniqueName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> deletePersistedImagePath(String? path) async {
  if (path == null || path.isEmpty) return;
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
