import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/intl.dart';

import 'api_service.dart';
import '../../storage_service.dart';

class TaiService {
  static const String _keyDbPath = 'tai_db_path';

  /// 获取用户上次设置的数据库路径
  static Future<String?> getSavedDbPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDbPath);
  }

  /// 保存数据库路径
  static Future<void> saveDbPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDbPath, path);
  }

  /// 验证路径是否是有效的 Tai 数据库
  static Future<bool> validateDb(String path) async {
    try {
      if (!File(path).existsSync()) return false;
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      // 检查关键表是否存在
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('DailyLogModels','AppModels')"
      );
      await db.close();
      return tables.length == 2;
    } catch (e) {
      return false;
    }
  }

  /// 读取指定日期的屏幕时间数据
  /// 返回格式与 ApiService.uploadScreenTime 的 apps 参数一致
  static Future<List<Map<String, dynamic>>> readDailyStats({
    required String dbPath,
    required String date, // yyyy-MM-dd
  }) async {
    try {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      final rows = await db.rawQuery('''
        SELECT
          COALESCE(NULLIF(a.Alias, ''), a.Name) AS app_name,
          SUM(d.Time) AS duration
        FROM DailyLogModels d
        JOIN AppModels a ON d.AppModelID = a.ID
        WHERE substr(d.Date, 1, 10) = ?
        GROUP BY a.ID
        ORDER BY duration DESC
      ''', [date]);

      await db.close();

      return rows.map((r) => {
        'app_name': r['app_name'] as String,
        'duration': r['duration'] as int,
      }).toList();
    } catch (e) {
      debugPrint('读取 Tai 数据库失败: $e');
      return [];
    }
  }

  /// 同步今日数据到云端
  static Future<bool> syncToCloud(int userId) async {
    final dbPath = await getSavedDbPath();
    if (dbPath == null || dbPath.isEmpty) {
      debugPrint('Tai 数据库路径未设置');
      return false;
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final apps = await readDailyStats(dbPath: dbPath, date: today);
    if (apps.isEmpty) return false;

    final ok = await ApiService.uploadScreenTime(
      userId: userId,
      deviceName: 'Windows-PC',  // 可进一步读取真实机器名
      date: today,
      apps: apps,
    );

    if (ok) {
      final cloudStats = await ApiService.fetchScreenTime(userId, today);
      await StorageService.saveScreenTimeCache(cloudStats);
      await StorageService.updateLastScreenTimeSync();
      debugPrint('Tai 屏幕时间同步完成，共 ${apps.length} 条应用数据');
    }

    return ok;
  }

  static Future<String?> detectDefaultPath() async {
    if (!Platform.isWindows) return null;
    final appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isEmpty) return null;
    final defaultPath = '$appData\\Tai\\data.db';
    if (File(defaultPath).existsSync()) return defaultPath;
    return null;
  }
}