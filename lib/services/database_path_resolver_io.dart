import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

Future<String> resolveDatabasePath(String targetName) async {
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux) {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(join(supportDir.path, 'databases'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final targetPath = join(dbDir.path, targetName);
    await migrateLegacyFfiDatabaseIfNeeded(targetName, targetPath);
    // debugPrint('📁 Database path: $targetPath');
    return targetPath;
  }

  final dbPath = await getDatabasesPath();
  return join(dbPath, targetName);
}

Future<void> migrateLegacyFfiDatabaseIfNeeded(
    String targetName, String targetPath) async {
  try {
    final targetFile = File(targetPath);
    if (await targetFile.exists()) return;

    final legacyPath = absolute(
      join('.dart_tool', 'sqflite_common_ffi', 'databases', targetName),
    );
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) return;

    await legacyFile.copy(targetPath);
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('$legacyPath$suffix');
      if (await sidecar.exists()) {
        await sidecar.copy('$targetPath$suffix');
      }
    }
    // debugPrint('✅ Database: 已从旧 FFI 路径迁移到 AppData: $targetPath');
  } catch (e) {
    // debugPrint('⚠️ Database: 旧 FFI 数据库迁移失败: $e');
  }
}
