import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../services/screen_time_service.dart';

class PermissionHandler {
  final BuildContext context;
  final MethodChannel platform;
  final Function(Map<String, PermissionStatus?>) onUpdateStatuses;
  final Function(bool) onUpdateChecking;

  PermissionHandler({
    required this.context,
    required this.platform,
    required this.onUpdateStatuses,
    required this.onUpdateChecking,
  });

  static const List<Map<String, dynamic>> permissionDefs = [
    {
      'key': 'notification',
      'label': '通知',
      'desc': '课程提醒、待办闹钟、下载进度推送',
      'icon': Icons.notifications_outlined,
      'color': Colors.blue,
      'critical': true,
    },
    {
      'key': 'storage',
      'label': '存储读写',
      'desc': '导入课表文件、下载版本更新安装包',
      'icon': Icons.folder_outlined,
      'color': Colors.orange,
      'critical': false,
    },
    {
      'key': 'usage_stats',
      'label': '应用使用情况',
      'desc': '屏幕时间统计功能（统计各 App 使用时长）',
      'icon': Icons.bar_chart_outlined,
      'color': Colors.purple,
      'critical': false,
    },
    {
      'key': 'request_install',
      'label': '安装未知来源应用',
      'desc': '允许应用内直接安装版本更新包',
      'icon': Icons.install_mobile_outlined,
      'color': Colors.teal,
      'critical': false,
    },
    {
      'key': 'exact_alarm',
      'label': '精确提醒',
      'desc': '保活核心权限：App 被杀后仍能在准确时刻推送待办/课程提醒',
      'icon': Icons.alarm_outlined,
      'color': Colors.red,
      'critical': true,
    },
  ];

  Future<void> checkAllPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    onUpdateChecking(true);

    final Map<String, PermissionStatus> results = {};

    results['notification'] = await Permission.notification.status;

    if (Platform.isAndroid) {
      final storageStatus = await Permission.storage.status;
      final manageStatus = await Permission.manageExternalStorage.status;
      results['storage'] = (storageStatus.isGranted || manageStatus.isGranted)
          ? PermissionStatus.granted
          : storageStatus;

      final bool hasUsage = await ScreenTimeService.checkPermission();
      results['usage_stats'] =
          hasUsage ? PermissionStatus.granted : PermissionStatus.denied;

      results['request_install'] =
          await Permission.requestInstallPackages.status;

      try {
        final bool granted =
            await platform.invokeMethod<bool>('checkExactAlarmPermission') ??
                true;
        results['exact_alarm'] =
            granted ? PermissionStatus.granted : PermissionStatus.denied;
      } catch (_) {
        results['exact_alarm'] = PermissionStatus.granted;
      }
    } else {
      results['storage'] = await Permission.storage.status;
      results['usage_stats'] = PermissionStatus.granted;
      results['request_install'] = PermissionStatus.granted;
      results['exact_alarm'] = PermissionStatus.granted;
    }

    onUpdateStatuses(results);
    onUpdateChecking(false);
  }

  Future<void> requestOrOpenPermission(String key) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    switch (key) {
      case 'notification':
        final status = await Permission.notification.request();
        if (status.isPermanentlyDenied) await openAppSettings();
        break;
      case 'storage':
        if (Platform.isAndroid) {
          final status = await Permission.manageExternalStorage.request();
          if (status.isPermanentlyDenied || status.isDenied) {
            await openAppSettings();
          }
        } else {
          final status = await Permission.storage.request();
          if (status.isPermanentlyDenied) await openAppSettings();
        }
        break;
      case 'usage_stats':
        await ScreenTimeService.openSettings();
        break;
      case 'request_install':
        final status = await Permission.requestInstallPackages.request();
        if (status.isPermanentlyDenied || status.isDenied) {
          await openAppSettings();
        }
        break;
      case 'exact_alarm':
        try {
          await platform.invokeMethod('openExactAlarmSettings');
        } catch (_) {
          await openAppSettings();
        }
        break;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    await checkAllPermissions();
  }
}
