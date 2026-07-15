import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../services/permission_request_coordinator.dart';
import '../../../utils/app_platform.dart';

class PermissionHandler {
  final BuildContext context;
  final MethodChannel platform;
  final Function(Map<String, PermissionStatus?>) onUpdateStatuses;
  final Function(bool) onUpdateChecking;
  final PermissionResultCallback? onPermissionResult;
  late final PermissionRequestCoordinator _coordinator;

  PermissionHandler({
    required this.context,
    required this.platform,
    required this.onUpdateStatuses,
    required this.onUpdateChecking,
    this.onPermissionResult,
  }) {
    _coordinator = PermissionRequestCoordinator(
      context: context,
      platformChannel: platform,
      onResult: onPermissionResult,
    );
  }

  static const List<Map<String, dynamic>> permissionDefs = [
    {
      'key': 'notification',
      'label': '通知',
      'desc': '课程提醒、待办闹钟、下载进度推送',
      'icon': Icons.notifications_outlined,
      'critical': true,
    },
    {
      'key': 'storage',
      'label': '存储读写',
      'desc': '导入课表文件、下载版本更新安装包',
      'icon': Icons.folder_outlined,
      'critical': false,
    },
    {
      'key': 'usage_stats',
      'label': '应用使用情况',
      'desc': '屏幕时间统计功能（统计各 App 使用时长）',
      'icon': Icons.bar_chart_outlined,
      'critical': false,
    },
    {
      'key': 'request_install',
      'label': '安装未知来源应用',
      'desc': '允许应用内直接安装版本更新包',
      'icon': Icons.install_mobile_outlined,
      'critical': false,
    },
    {
      'key': 'exact_alarm',
      'label': '精确提醒',
      'desc': '保活核心权限：App 被杀后仍能在准确时刻推送待办/课程提醒',
      'icon': Icons.alarm_outlined,
      'critical': true,
    },
  ];

  Future<void> checkAllPermissions() async {
    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) return;
    onUpdateChecking(true);
    try {
      final results = <String, PermissionStatus>{
        'notification':
            await _coordinator.status(AppPermissionKind.notification),
        'storage': await _coordinator.status(AppPermissionKind.storage),
        'usage_stats': await _coordinator.status(AppPermissionKind.usageStats),
        'request_install':
            await _coordinator.status(AppPermissionKind.requestInstall),
        'exact_alarm': await _coordinator.status(AppPermissionKind.exactAlarm),
      };
      onUpdateStatuses(results);
    } finally {
      onUpdateChecking(false);
    }
  }

  Future<PermissionRequestResult?> requestOrOpenPermission(
    String key, {
    PermissionResultCallback? onResult,
  }) async {
    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) return null;
    final permission = _permissionForKey(key);
    if (permission == null) return null;

    onUpdateChecking(true);
    try {
      final result = await _coordinator.request(
        permission,
        onResult: onResult,
      );
      await checkAllPermissions();
      return result;
    } finally {
      onUpdateChecking(false);
    }
  }

  AppPermissionKind? _permissionForKey(String key) => switch (key) {
        'notification' => AppPermissionKind.notification,
        'storage' => AppPermissionKind.storage,
        'usage_stats' => AppPermissionKind.usageStats,
        'request_install' => AppPermissionKind.requestInstall,
        'exact_alarm' => AppPermissionKind.exactAlarm,
        _ => null,
      };

  void dispose() => _coordinator.dispose();
}
