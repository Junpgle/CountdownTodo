import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/tai_service.dart';
import '../services/storage/user_session_storage.dart';
import '../utils/app_platform.dart';
import '../../storage_service.dart';

class ScreenTimeService {
  static const _channel = MethodChannel('com.math_quiz_app/screen_time');
  static const int syncIntervalMinutes = 2;
  static Future<void>? _backgroundSyncFuture;

  /// 缓存被后台同步更新后的轻量通知，供展示层重新读取当前快照。
  static ValueNotifier<int> get dataRefreshNotifier =>
      StorageService.screenTimeRefreshNotifier;

  static Future<bool> checkPermission() async {
    if (kIsWeb || !AppPlatform.isAndroid) return true;
    try {
      return await _channel.invokeMethod('checkUsagePermission');
    } catch (e) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (AppPlatform.isAndroid) {
      await _channel.invokeMethod('openUsageSettings');
    }
  }

  /// 获取屏幕使用时间（UI 调用入口）
  static Future<List<dynamic>> getScreenTimeData(int userId) async {
    // 1. 使用优化后的 getScreenTimeCache (内部自带日期失效校验)
    List<dynamic> cachedData = await StorageService.getScreenTimeCache();

    // 如果是桌面端且无缓存，必须同步一次
    bool isDesktop = !kIsWeb && AppPlatform.isDesktop;

    if (isDesktop && cachedData.isEmpty) {
      await _performBackgroundSync(userId);
      return await StorageService.getScreenTimeCache();
    }

    // 2. 检查是否需要静默刷新
    DateTime? lastSync = await StorageService.getLastScreenTimeSync();
    bool needSync = lastSync == null ||
        DateTime.now().difference(lastSync).inMinutes >= syncIntervalMinutes;

    if (needSync) {
      // 异步执行，不阻塞 UI 返回缓存数据
      unawaited(_performBackgroundSync(userId));
    }

    return cachedData;
  }

  /// 核心同步逻辑
  ///
  /// 多个入口可能在同一个缓存失效窗口请求数据；合并为同一次采集、上传和
  /// 拉取，避免重复调用原生接口及网络请求。
  static Future<void> _performBackgroundSync(int userId) {
    return _backgroundSyncFuture ??=
        _performBackgroundSyncInternal(userId).whenComplete(() {
      _backgroundSyncFuture = null;
    });
  }

  static Future<void> _performBackgroundSyncInternal(int userId) async {
    if (kIsWeb) return;

    try {
      String? username = await UserSessionStorage.getLoginSession();
      if (username == null) return;

      bool hasScreenTimeData = false;

      // 1. 获取本机干干净净的数据，存入【专用上传缓存】
      if (AppPlatform.isAndroid) {
        bool hasPermission = await checkPermission();
        if (!hasPermission) {
          // debugPrint("⚠️ Android 屏幕使用权限未授予，跳过屏幕时间采集，其他数据继续同步");
        } else {
          final dynamic stats =
              await _channel.invokeMethod('getScreenTimeData');

          // 🚀 适配 Android 返回的新格式: { "date": "yyyy-MM-dd", "apps": [...] }
          if (stats is Map &&
              stats['apps'] is List &&
              (stats['apps'] as List).isNotEmpty) {
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
      } else if (AppPlatform.isDesktop) {
        final List<Map<String, dynamic>> apps =
            await TaiService.getTodayStats();
        if (apps.isNotEmpty) {
          String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
          await StorageService.saveLocalScreenTime(
              {'date': today, 'apps': apps});
          hasScreenTimeData = true;
        }
      }

      final pendingPackage = await StorageService.getLocalScreenTimePackage();
      final hasPendingScreenTimeData = pendingPackage?['apps'] is List &&
          (pendingPackage?['apps'] as List).isNotEmpty;

      // 2. 将本机纯净数据或此前失败后保留的数据推送到云端。
      // 🚀 优先使用独立的 /api/screen_time 接口上传屏幕时间数据
      if (hasScreenTimeData || hasPendingScreenTimeData) {
        String deviceName = await UserSessionStorage.getDeviceFriendlyName();
        final uploaded =
            await StorageService.syncScreenTimeAlone(username, deviceName);
        if (!uploaded) return;
      }

      // 3. 仅拉取多端聚合后的屏幕时间总表。该任务不应每两分钟再带起
      // 待办、倒计时、习惯等整套业务同步。
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      List<dynamic> cloudStats = await ApiService.fetchScreenTime(
        userId,
        today,
        throwOnError: true,
      );

      if (cloudStats.isNotEmpty) {
        // 4. 用云端总表覆盖【UI显示缓存】
        await StorageService.saveScreenTimeCache(cloudStats);
      }

      // 拉取完成后再推进水位线；上传失败时保留待上传数据并尽快重试。
      await StorageService.updateLastScreenTimeSync();
    } catch (e) {
      // debugPrint("屏幕时间后台同步失败: $e");
    }
  }

  static Future<void> syncScreenTime(int userId) async {
    await _performBackgroundSync(userId);
  }
}
