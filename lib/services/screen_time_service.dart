import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/tai_service.dart';
import '../../storage_service.dart';

class ScreenTimeService {
  static const _channel = MethodChannel('com.math_quiz_app/screen_time');
  static const int SYNC_INTERVAL_MINUTES = 2;

  static Future<bool> checkPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod('checkUsagePermission');
    } catch (e) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('openUsageSettings');
    }
  }

  static Future<List<dynamic>> getScreenTimeData(int userId) async {
    // 桌面端：缓存为空时先等待同步完成再返回，有缓存则后台静默更新
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      List<dynamic> cachedData = await StorageService.getScreenTimeCache();
      if (cachedData.isEmpty) {
        await _performBackgroundSync(userId);
        return await StorageService.getScreenTimeCache();
      }
      _performBackgroundSync(userId); // 后台静默刷新
      return cachedData;
    }

    // Android 原有逻辑
    List<dynamic> cachedData = await StorageService.getScreenTimeCache();
    DateTime? lastSync = await StorageService.getLastScreenTimeSync();
    bool needSync = lastSync == null ||
        DateTime.now().difference(lastSync).inMinutes >= SYNC_INTERVAL_MINUTES;
    if (needSync) {
      _performBackgroundSync(userId);
    }
    return cachedData;
  }

  static Future<void> _performBackgroundSync(int userId) async {
    if (kIsWeb) return;

    try {
      if (Platform.isAndroid) {
        if (!(await checkPermission())) return;

        final List<dynamic>? stats = await _channel.invokeMethod('getScreenTimeData');
        if (stats == null || stats.isEmpty) return;

        String deviceName = stats.first['device_type'] ?? "Android-Phone";
        final List<Map<String, dynamic>> apps = stats.map((e) => {
          "app_name": e["app_name"],
          "duration": e["duration"],
        }).toList();

        String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        bool uploadOk = await ApiService.uploadScreenTime(
          userId: userId,
          deviceName: deviceName,
          date: today,
          apps: apps,
        );

        if (uploadOk) {
          var cloudStats = await ApiService.fetchScreenTime(userId, today);
          await StorageService.saveScreenTimeCache(cloudStats);
          await StorageService.updateLastScreenTimeSync();
          debugPrint("Android 屏幕时间同步完成");
        }

      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final dbPath = await TaiService.getSavedDbPath();
        if (dbPath == null || dbPath.isEmpty) {
          debugPrint("Tai 数据库路径未设置，跳过桌面端同步");
          return;
        }

        await TaiService.syncToCloud(userId);

        String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        var cloudStats = await ApiService.fetchScreenTime(userId, today);
        if (cloudStats.isNotEmpty) {
          await StorageService.saveScreenTimeCache(cloudStats);
          await StorageService.updateLastScreenTimeSync();
          debugPrint("桌面端 Tai 屏幕时间同步完成");
        }
      }
    } catch (e) {
      debugPrint("屏幕时间后台同步失败: $e");
    }
  }

  static Future<void> syncScreenTime(int userId) async {
    await _performBackgroundSync(userId);
  }
}