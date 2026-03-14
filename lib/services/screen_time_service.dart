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
      // 获取当前用户名（用于 syncData）
      String? username = await StorageService.getLoginSession();
      if (username == null) return;

      if (Platform.isAndroid) {
        if (!(await checkPermission())) return;

        // 1. 从原生层抓取原始数据
        final List<dynamic>? stats = await _channel.invokeMethod('getScreenTimeData');
        if (stats == null || stats.isEmpty) return;

        // 2. 立即存入本地缓存 (这会更新 KEY_LAST_SCREEN_TIME_SYNC 时间戳)
        // 这样 StorageService.syncData 就会认为这是“今日最新”数据
        await StorageService.saveScreenTimeCache(stats);

        // 3. 调用统一的增量同步接口
        // 它会把刚才存入 cache 的数据通过 screenPayload 发送给后端
        await StorageService.syncData(username);

        debugPrint("Android 屏幕时间同步流程完成 (经由 syncData)");

      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // 1. 从 Tai 数据库读取原始数据
        final List<Map<String, dynamic>> apps = await TaiService
            .getTodayStats();
        if (apps.isEmpty) return;

        // 2. 立即存入本地缓存（确保本地先看到数据）
        // 这也会更新本地的时间戳，让随后的 syncData 识别到这是今日数据
        await StorageService.saveScreenTimeCache(apps);

        // 3. 统一调用 syncData 进行增量同步
        // syncData 内部会使用正确的设备名： "windows (PC)"
        String? username = await StorageService.getLoginSession();
        if (username != null) {
          await StorageService.syncData(username);
          debugPrint("桌面端通过统一接口同步完成");
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