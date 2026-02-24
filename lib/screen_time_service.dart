import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../api_service.dart';

class ScreenTimeService {
  static const _channel = MethodChannel('com.math_quiz_app/screen_time');

  // 检查 Android 权限
  static Future<bool> checkPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod('checkUsagePermission');
    } catch (e) {
      return false;
    }
  }

  // 打开系统设置开启权限
  static Future<void> openSettings() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('openUsageSettings');
    }
  }

  // 核心同步逻辑：读取原生数据并推送到云端
  static Future<void> syncScreenTime(int userId) async {
    if (kIsWeb || !Platform.isAndroid) return;

    bool hasPermission = await checkPermission();
    if (!hasPermission) return;

    try {
      // 1. 获取原生统计
      final List<dynamic>? stats = await _channel.invokeMethod('getScreenTimeData');
      if (stats == null || stats.isEmpty) return;

      // 2. 格式化数据
      final List<Map<String, dynamic>> apps = stats.map((e) => {
        "app_name": e["app_name"],
        "duration": e["duration"],
      }).toList();

      // 3. 上传到云端 (后端会根据 ON CONFLICT 自动更新)
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await ApiService.uploadScreenTime(
        userId: userId,
        deviceName: "Android Phone",
        date: today,
        apps: apps,
      );
    } catch (e) {
      print("屏幕时间同步错误: $e");
    }
  }
}