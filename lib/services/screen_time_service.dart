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
    bool isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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

      bool hasScreenTimeData = false;

      // 1. 获取本机干干净净的数据，存入【专用上传缓存】
      if (Platform.isAndroid) {
        bool hasPermission = await checkPermission();
        if (!hasPermission) {
          debugPrint("⚠️ Android 屏幕使用权限未授予，跳过屏幕时间采集，其他数据继续同步");
        } else {
          final dynamic stats =
              await _channel.invokeMethod('getScreenTimeData');

          // 🚀 适配 Android 返回的新格式: { "date": "yyyy-MM-dd", "apps": [...] }
          if (stats is Map && stats['apps'] != null) {
            await StorageService.saveLocalScreenTime(stats);
            hasScreenTimeData = true;
          } else if (stats is List && stats.isNotEmpty) {
            // 向后兼容旧格式
            String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
            await StorageService.saveLocalScreenTime(
                {'date': today, 'apps': stats});
            hasScreenTimeData = true;
          }
        }
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final List<Map<String, dynamic>> apps =
            await TaiService.getTodayStats();
        if (apps.isNotEmpty) {
          String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
          await StorageService.saveLocalScreenTime(
              {'date': today, 'apps': apps});
          hasScreenTimeData = true;
        }
      }

      // 2. 将本机纯净数据推送到云端
      // 🚀 优先使用独立的 /api/screen_time 接口上传屏幕时间数据
      if (hasScreenTimeData) {
        String deviceName = await StorageService.getDeviceFriendlyName();
        await StorageService.syncScreenTimeAlone(username, deviceName);
      }

      await StorageService.syncData(username);

      // 🚀 只要推送成功，即便云端还没聚合好，也更新本地同步水位线，防止 2 分钟死循环
      await StorageService.updateLastScreenTimeSync();

      // 3. 强制向云端索要多端聚合后的“完美总表”
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      List<dynamic> cloudStats =
          await ApiService.fetchScreenTime(userId, today);

      if (cloudStats.isNotEmpty) {
        // 4. 用云端总表覆盖【UI显示缓存】
        await StorageService.saveScreenTimeCache(cloudStats);
      }
    } catch (e) {
      debugPrint("屏幕时间后台同步失败: $e");
    }
  }

  static Future<void> syncScreenTime(int userId) async {
    await _performBackgroundSync(userId);
  }
}
