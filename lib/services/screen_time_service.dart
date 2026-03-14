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
        final dbPath = await TaiService.getSavedDbPath();
        if (dbPath == null || dbPath.isEmpty) return;

        // 桌面端 Tai 的同步逻辑
        await TaiService.syncToCloud(userId);

        // 同步完成后，从云端拉取最新的“已分类”结果更新本地缓存
        String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        var cloudStats = await ApiService.fetchScreenTime(userId, today);
        if (cloudStats.isNotEmpty) {
          await StorageService.saveScreenTimeCache(cloudStats);
          debugPrint("桌面端屏幕时间已从云端反哺本地缓存");
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