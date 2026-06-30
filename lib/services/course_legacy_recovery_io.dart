import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../utils/app_platform.dart';
import 'environment_service.dart';

Future<List<CourseItem>> recoverLegacyCoursesFromSql(String username) async {
  if (!(AppPlatform.isWindows || AppPlatform.isLinux)) return [];

  final envPrefix = EnvironmentService.isTest ? 'test_v5_' : 'v4_';
  final candidateNames = <String>{
    '${envPrefix}uni_sync_$username.db',
    'v4_uni_sync_$username.db',
    'uni_sync_$username.db',
    EnvironmentService.dbName,
    'v4_uni_sync.db',
  };

  final candidatePaths = <String>{
    for (final dbName in candidateNames)
      absolute(join('.dart_tool', 'sqflite_common_ffi', 'databases', dbName)),
    for (final dbName in candidateNames)
      absolute(join(
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        dbName,
      )),
    for (final dbName in candidateNames)
      absolute(join(
        'build',
        'windows',
        'x64',
        'runner',
        'Release',
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        dbName,
      )),
  };

  for (final legacyPath in candidatePaths) {
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) continue;

    Database? legacyDb;
    try {
      legacyDb = await openDatabase(legacyPath, readOnly: true);
      final tableRows = await legacyDb.query(
        'sqlite_master',
        columns: ['name'],
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'courses'],
        limit: 1,
      );
      if (tableRows.isEmpty) continue;

      final maps = await legacyDb.query(
        'courses',
        where: 'IFNULL(is_deleted, 0) = 0',
        orderBy: 'date ASC, start_time ASC',
      );
      if (maps.isEmpty) continue;

      debugPrint('✅ [Course] 已从旧 FFI 数据库恢复 ${maps.length} 条课表: $legacyPath');
      return maps.map((m) => CourseItem.fromJson(m)).toList();
    } catch (e) {
      debugPrint('⚠️ [Course] 旧 FFI 课表恢复失败 ($legacyPath): $e');
    } finally {
      await legacyDb?.close();
    }
  }

  return [];
}
