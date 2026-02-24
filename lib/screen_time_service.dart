import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../api_service.dart';
import '../storage_service.dart';

class ScreenTimeService {
  static const _channel = MethodChannel('com.math_quiz_app/screen_time');

  // 设定同步间隔（例如 2 分钟）
  static const int SYNC_INTERVAL_MINUTES = 2;

  /// 检查 Android 权限
  static Future<bool> checkPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod('checkUsagePermission');
    } catch (e) {
      return false;
    }
  }

  /// 打开系统设置开启权限
  static Future<void> openSettings() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('openUsageSettings');
    }
  }

  /// 获取屏幕时间数据
  /// 逻辑：优先获取本地缓存。如果距离上次同步超过 5 分钟，则触发后台同步。
  static Future<List<dynamic>> getScreenTimeData(int userId) async {
    // 1. 优先获取本地缓存
    List<dynamic> cachedData = await StorageService.getScreenTimeCache();

    // 2. 检查是否需要同步
    DateTime? lastSync = await StorageService.getLastScreenTimeSync();
    DateTime now = DateTime.now();

    bool needSync = lastSync == null ||
        now.difference(lastSync).inMinutes >= SYNC_INTERVAL_MINUTES;

    if (needSync) {
      // 触发异步后台同步，不阻塞当前 UI 返回缓存数据
      _performBackgroundSync(userId);
    }

    return cachedData;
  }

  /// 核心同步逻辑：读取原生数据、上报云端、拉取汇总、存入缓存
  static Future<void> _performBackgroundSync(int userId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!(await checkPermission())) return;

    try {
      // A. 从原生 Android 获取应用使用统计
      final List<dynamic>? stats = await _channel.invokeMethod('getScreenTimeData');
      if (stats == null || stats.isEmpty) return;

      // 从原生返回的数据中提取设备类型
      String deviceName = stats.first['device_type'] ?? "Android-Phone";

      // 格式化为 API 接收的格式
      final List<Map<String, dynamic>> apps = stats.map((e) => {
        "app_name": e["app_name"],
        "duration": e["duration"], // 秒
      }).toList();

      // B. 上报到后端
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      bool uploadOk = await ApiService.uploadScreenTime(
        userId: userId,
        deviceName: deviceName,
        date: today,
        apps: apps,
      );

      if (uploadOk) {
        // C. 上报成功后，拉取最新的云端汇总（包含其他设备的数据）
        var cloudStats = await ApiService.fetchScreenTime(userId, today);

        // D. 更新本地缓存和同步时间戳
        await StorageService.saveScreenTimeCache(cloudStats);
        await StorageService.updateLastScreenTimeSync();

        debugPrint("屏幕时间同步完成，数据已缓存");
      }
    } catch (e) {
      debugPrint("屏幕时间后台同步失败: $e");
    }
  }

  /// 强制同步方法
  /// 修复：对应 dashboard 中的调用名，确保编译通过
  static Future<void> syncScreenTime(int userId) async {
    await _performBackgroundSync(userId);
  }
}