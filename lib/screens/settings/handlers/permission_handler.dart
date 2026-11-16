import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const List<Map<String, dynamic>> _allPermissionDefs = [
    {
      'key': 'notification',
      'label': '通知',
      'desc': '用于推送课程上课提醒、待办闹钟、专注计时结束及版本下载进度',
      'icon': Icons.notifications_outlined,
      'critical': true,
      'platforms': {'android', 'ios', 'macos', 'windows', 'linux'},
    },
    {
      'key': 'exact_alarm',
      'label': '精确提醒',
      'desc': '保活核心权限：确保 App 在后台或被清理后仍能在准确时刻准时推送待办与课程提醒',
      'icon': Icons.alarm_outlined,
      'critical': true,
      'platforms': {'android'},
    },
    {
      'key': 'battery_optimization',
      'label': '忽略电池优化',
      'desc': '减少锁屏或后台运行时专注计时、定时提醒与实时同步被系统省电策略中断',
      'icon': Icons.battery_saver_outlined,
      'critical': false,
      'platforms': {'android'},
    },
    {
      'key': 'storage',
      'label': '存储读写',
      'desc': '用于导入课表文件、导出/恢复本地数据备份以及保存版本更新安装包',
      'icon': Icons.folder_outlined,
      'critical': false,
      'platforms': {'android'},
    },
    {
      'key': 'usage_stats',
      'label': '应用使用情况',
      'desc': '用于时间日志中的屏幕时间统计，读取各应用使用时长并生成今日汇总与分析',
      'icon': Icons.bar_chart_outlined,
      'critical': false,
      'platforms': {'android'},
    },
    {
      'key': 'calendar',
      'label': '日历读写',
      'desc': '用于读取手机本地日历日程并展示在 App 内（首页、周视图等），以及将课程、待办和规划写入系统日历',
      'icon': Icons.event_available_outlined,
      'critical': false,
      'platforms': {'android', 'ios', 'macos'},
    },
    {
      'key': 'location',
      'label': '位置信息',
      'desc': '用于让 AI 助手在函数调用中按需查询当前所在城市与位置，结合时区提供更准确的本地建议（可提前授权）',
      'icon': Icons.location_on_outlined,
      'critical': false,
      'platforms': {'android', 'ios', 'macos'},
    },
    {
      'key': 'local_network',
      'label': '局域网访问',
      'desc': '用于发现同一局域网下的同账号设备，实现局域网互传与数据同步',
      'icon': Icons.wifi_tethering_outlined,
      'critical': false,
      'platforms': {'android'},
    },
    {
      'key': 'live_updates',
      'label': '实时通知',
      'desc': '用于在支持的 Android 16+ 设备状态栏与锁屏展示番茄专注等实时活动进度',
      'icon': Icons.bolt_outlined,
      'critical': false,
      'platforms': {'android'},
    },
    {
      'key': 'request_install',
      'label': '安装未知来源应用',
      'desc': '用于在应用内下载新版安装包后直接拉起系统安装界面完成更新',
      'icon': Icons.install_mobile_outlined,
      'critical': false,
      'platforms': {'android'},
    },
  ];

  static List<Map<String, dynamic>> defsForPlatform({
    required bool isWeb,
    required bool isAndroid,
    required bool isIOS,
    required bool isMacOS,
    required bool isWindows,
  }) {
    if (isWeb) return const [];
    final platformTag = isAndroid
        ? 'android'
        : isIOS
        ? 'ios'
        : isMacOS
        ? 'macos'
        : isWindows
        ? 'windows'
        : 'linux';
    return _allPermissionDefs
        .where((def) => (def['platforms'] as Set<String>).contains(platformTag))
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> get permissionDefs => defsForPlatform(
    isWeb: AppPlatform.isWeb,
    isAndroid: AppPlatform.isAndroid,
    isIOS: AppPlatform.isIOS,
    isMacOS: AppPlatform.isMacOS,
    isWindows: AppPlatform.isWindows,
  );

  Future<void> checkAllPermissions() async {
    onUpdateChecking(true);
    try {
      final results = <String, PermissionStatus>{};
      for (final def in permissionDefs) {
        final key = def['key'] as String;
        final permission = _permissionForKey(key);
        if (permission != null) {
          results[key] = await _coordinator.status(permission);
        }
      }
      onUpdateStatuses(results);
    } finally {
      onUpdateChecking(false);
    }
  }

  Future<PermissionRequestResult?> requestOrOpenPermission(
    String key, {
    PermissionResultCallback? onResult,
  }) async {
    final permission = _permissionForKey(key);
    if (permission == null) return null;

    onUpdateChecking(true);
    try {
      final result = await _coordinator.request(
        permission,
        onResult: onResult,
        fallbackToSettingsOnDenied: true,
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
    'battery_optimization' => AppPermissionKind.batteryOptimization,
    'calendar' => AppPermissionKind.calendar,
    'location' => AppPermissionKind.location,
    'live_updates' => AppPermissionKind.liveUpdates,
    'local_network' => AppPermissionKind.localNetwork,
    _ => null,
  };

  void dispose() => _coordinator.dispose();

  Future<void> revokeAllAgreements() async {
    final prefs = await SharedPreferences.getInstance();
    for (final permission in AppPermissionKind.values) {
      final agreedKey = 'permission_agreed_${permission.name}';
      await prefs.remove(agreedKey);
    }
  }
}
