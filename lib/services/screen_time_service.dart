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

  /// 获取屏幕使用时间（UI 调用入口）
  static Future<List<dynamic>> getScreenTimeData(int userId) async {
    // 1. 使用优化后的 getScreenTimeCache (内部自带日期失效校验)
    List<dynamic> cachedData = await StorageService.getScreenTimeCache();

    // 如果是桌面端且无缓存，必须同步一次
    bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isDesktop && cachedData.isEmpty) {
      await _performBackgroundSync(userId);
      return await StorageService.getScreenTimeCache();
    }

    // 2. 检查是否需要静默刷新
    DateTime? lastSync = await StorageService.getLastScreenTimeSync();
    bool needSync = lastSync == null ||
        DateTime.now().difference(lastSync).inMinutes >= SYNC_INTERVAL_MINUTES;

    if (needSync) {
      // 异步执行，不阻塞 UI 返回缓存数据
      _performBackgroundSync(userId);
    }

    return cachedData;
  }

  /// 核心同步逻辑
  static Future<void> _performBackgroundSync(int userId) async {
    if (kIsWeb) return;

    try {
      String? username = await StorageService.getLoginSession();
      if (username == null) return;

      // 1. 获取本机干干净净的数据，存入【专用上传缓存】
      if (Platform.isAndroid) {
        if (!(await checkPermission())) return;
        final List<dynamic>? stats = await _channel.invokeMethod('getScreenTimeData');
        if (stats != null && stats.isNotEmpty) {
          await StorageService.saveLocalScreenTime(stats); // 🚀 改用新的方法
        }
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final List<Map<String, dynamic>> apps = await TaiService.getTodayStats();
        if (apps.isNotEmpty) {
          await StorageService.saveLocalScreenTime(apps); // 🚀 改用新的方法
        }
      }

      // 2. 将本机纯净数据推送到云端
      await StorageService.syncData(username);
      debugPrint("📤 本机屏幕时间已推送到云端");

      // 3. 强制向云端索要多端聚合后的“完美总表”
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      List<dynamic> cloudStats = await ApiService.fetchScreenTime(userId, today);

      if (cloudStats.isNotEmpty) {
        // 4. 用云端总表覆盖【UI显示缓存】
        await StorageService.saveScreenTimeCache(cloudStats); // 🚀 只有这里用旧方法
        debugPrint("📥 成功拉取云端聚合数据，准备刷新 UI！");
      }

    } catch (e) {
      debugPrint("屏幕时间后台同步失败: $e");
    }
  }

  static Future<void> syncScreenTime(int userId) async {
    await _performBackgroundSync(userId);
  }
}