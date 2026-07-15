import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/app_platform.dart';
import 'band_sync_service.dart';
import 'screen_time_service.dart';

enum AppPermissionKind {
  notification,
  storage,
  usageStats,
  requestInstall,
  exactAlarm,
  batteryOptimization,
  calendar,
  liveUpdates,
  bandDeviceManagement,
}

extension AppPermissionKindDetails on AppPermissionKind {
  String get label => switch (this) {
        AppPermissionKind.notification => '通知',
        AppPermissionKind.storage => '存储读写',
        AppPermissionKind.usageStats => '应用使用情况',
        AppPermissionKind.requestInstall => '安装未知来源应用',
        AppPermissionKind.exactAlarm => '精确提醒',
        AppPermissionKind.batteryOptimization => '忽略电池优化',
        AppPermissionKind.calendar => '日历读写',
        AppPermissionKind.liveUpdates => '实时通知',
        AppPermissionKind.bandDeviceManagement => '小米手环设备管理',
      };

  String get rationale => switch (this) {
        AppPermissionKind.notification => '用于发送待办、课程和专注结束提醒。',
        AppPermissionKind.storage => '用于导入课表文件和保存版本更新安装包。',
        AppPermissionKind.usageStats => '用于统计各应用使用时长，生成屏幕时间分析。',
        AppPermissionKind.requestInstall => '用于在应用内安装已经下载的版本更新。',
        AppPermissionKind.exactAlarm => '用于在应用退出后仍按设定时间准时发送提醒。',
        AppPermissionKind.batteryOptimization => '用于减少锁屏后专注计时和实时同步被系统中断。',
        AppPermissionKind.calendar => '用于将课程、待办和计划写入 Android 系统日历。',
        AppPermissionKind.liveUpdates => '用于在支持的 Android 设备上展示实时活动和状态更新。',
        AppPermissionKind.bandDeviceManagement =>
          '用于向已连接的小米手环同步待办、课程、倒数日和专注状态。',
      };

  bool get opensDedicatedSettings => switch (this) {
        AppPermissionKind.usageStats ||
        AppPermissionKind.exactAlarm ||
        AppPermissionKind.batteryOptimization ||
        AppPermissionKind.liveUpdates =>
          true,
        _ => false,
      };
}

@immutable
class PermissionRequestResult {
  final AppPermissionKind permission;
  final PermissionStatus previousStatus;
  final PermissionStatus status;
  final bool openedSettings;
  final bool cancelledByUser;

  const PermissionRequestResult({
    required this.permission,
    required this.previousStatus,
    required this.status,
    required this.openedSettings,
    required this.cancelledByUser,
  });

  bool get granted => status.isGranted || status.isLimited;
  bool get changed => status != previousStatus;
}

typedef PermissionResultCallback = void Function(
    PermissionRequestResult result);
typedef PermissionStatusReader = Future<PermissionStatus> Function(
    AppPermissionKind permission);
typedef PermissionRequester = Future<PermissionStatus> Function(
    AppPermissionKind permission);
typedef PermissionSettingsOpener = Future<bool> Function(
    AppPermissionKind permission);

/// Coordinates permission prompts, settings round-trips and their UI feedback.
class PermissionRequestCoordinator with WidgetsBindingObserver {
  PermissionRequestCoordinator({
    required this.context,
    this.onResult,
    MethodChannel? platformChannel,
    PermissionStatusReader? statusReader,
    PermissionRequester? requester,
    PermissionSettingsOpener? settingsOpener,
  })  : _platformChannel = platformChannel ??
            const MethodChannel(
              'com.math_quiz.junpgle.com.math_quiz_app/notifications',
            ),
        _statusReaderOverride = statusReader,
        _requesterOverride = requester,
        _settingsOpenerOverride = settingsOpener {
    WidgetsBinding.instance.addObserver(this);
  }

  final BuildContext context;
  final PermissionResultCallback? onResult;
  final MethodChannel _platformChannel;
  final PermissionStatusReader? _statusReaderOverride;
  final PermissionRequester? _requesterOverride;
  final PermissionSettingsOpener? _settingsOpenerOverride;

  OverlayEntry? _rationaleEntry;
  Completer<bool>? _rationaleCompleter;
  bool _rationaleConfirmed = false;
  Completer<void>? _resumeCompleter;
  bool _leftApp = false;
  bool _disposed = false;
  Future<PermissionRequestResult>? _activeRequest;
  AppPermissionKind? _activePermission;

  Future<PermissionStatus> status(AppPermissionKind permission) {
    return _statusReaderOverride?.call(permission) ?? _readStatus(permission);
  }

  Future<PermissionRequestResult> request(
    AppPermissionKind permission, {
    PermissionResultCallback? onResult,
  }) async {
    final activeRequest = _activeRequest;
    if (activeRequest != null) {
      final activePermission = _activePermission;
      final result = await activeRequest;
      if (activePermission == permission) {
        onResult?.call(result);
        return result;
      }
    }

    _activePermission = permission;
    final request = _performRequest(permission);
    _activeRequest = request;
    try {
      final result = await request;
      this.onResult?.call(result);
      onResult?.call(result);
      return result;
    } finally {
      _activeRequest = null;
      _activePermission = null;
    }
  }

  Future<PermissionRequestResult> _performRequest(
      AppPermissionKind permission) async {
    final previousStatus = await status(permission);
    if (previousStatus.isGranted || previousStatus.isLimited) {
      return PermissionRequestResult(
        permission: permission,
        previousStatus: previousStatus,
        status: previousStatus,
        openedSettings: false,
        cancelledByUser: false,
      );
    }

    var openedSettings = false;
    final confirmed = await _showRationale(permission);
    if (!confirmed) {
      _hideRationale();
      return PermissionRequestResult(
        permission: permission,
        previousStatus: previousStatus,
        status: previousStatus,
        openedSettings: false,
        cancelledByUser: true,
      );
    }

    try {
      if (permission.opensDedicatedSettings ||
          previousStatus.isPermanentlyDenied) {
        openedSettings = await _openSettingsAndWait(permission);
      } else if (!previousStatus.isGranted && !previousStatus.isLimited) {
        final requestedStatus = await (_requesterOverride?.call(permission) ??
            _requestPermission(permission));
        if (requestedStatus.isPermanentlyDenied) {
          openedSettings = await _openSettingsAndWait(permission);
        } else if (permission == AppPermissionKind.storage ||
            permission == AppPermissionKind.requestInstall) {
          openedSettings = true;
        }
      }

      return PermissionRequestResult(
        permission: permission,
        previousStatus: previousStatus,
        status: await status(permission),
        openedSettings: openedSettings,
        cancelledByUser: false,
      );
    } finally {
      _hideRationale();
    }
  }

  Future<bool> _openSettingsAndWait(AppPermissionKind permission) async {
    _resumeCompleter = Completer<void>();
    _leftApp = false;

    final opened = await (_settingsOpenerOverride?.call(permission) ??
        _openPermissionSettings(permission));
    if (!opened) {
      _resumeCompleter = null;
      return false;
    }

    await _resumeCompleter!.future;
    _resumeCompleter = null;
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final completer = _resumeCompleter;
    if (completer == null || completer.isCompleted) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftApp = true;
    } else if (state == AppLifecycleState.resumed && _leftApp) {
      completer.complete();
    }
  }

  Future<PermissionStatus> _readStatus(AppPermissionKind permission) async {
    switch (permission) {
      case AppPermissionKind.notification:
        return Permission.notification.status;
      case AppPermissionKind.storage:
        if (AppPlatform.isAndroid) {
          final storage = await Permission.storage.status;
          if (await _usesManageExternalStorage()) {
            final managed = await Permission.manageExternalStorage.status;
            return managed.isGranted ? PermissionStatus.granted : managed;
          }
          return storage;
        }
        return Permission.storage.status;
      case AppPermissionKind.usageStats:
        return await ScreenTimeService.checkPermission()
            ? PermissionStatus.granted
            : PermissionStatus.denied;
      case AppPermissionKind.requestInstall:
        return Permission.requestInstallPackages.status;
      case AppPermissionKind.exactAlarm:
        try {
          final granted = await _platformChannel.invokeMethod<bool>(
                'checkExactAlarmPermission',
              ) ??
              true;
          return granted ? PermissionStatus.granted : PermissionStatus.denied;
        } on PlatformException {
          return PermissionStatus.granted;
        }
      case AppPermissionKind.batteryOptimization:
        return Permission.ignoreBatteryOptimizations.status;
      case AppPermissionKind.calendar:
        return Permission.calendarFullAccess.status;
      case AppPermissionKind.liveUpdates:
        try {
          final granted = await _platformChannel.invokeMethod<bool>(
                'checkLiveUpdatesPermission',
              ) ??
              true;
          return granted ? PermissionStatus.granted : PermissionStatus.denied;
        } on PlatformException {
          return PermissionStatus.granted;
        }
      case AppPermissionKind.bandDeviceManagement:
        final connection = await BandSyncService.getConnectionStatus();
        return connection['hasPermission'] == true
            ? PermissionStatus.granted
            : PermissionStatus.denied;
    }
  }

  Future<PermissionStatus> _requestPermission(
      AppPermissionKind permission) async {
    switch (permission) {
      case AppPermissionKind.notification:
        return Permission.notification.request();
      case AppPermissionKind.storage:
        if (AppPlatform.isAndroid && await _usesManageExternalStorage()) {
          return Permission.manageExternalStorage.request();
        }
        return Permission.storage.request();
      case AppPermissionKind.requestInstall:
        return Permission.requestInstallPackages.request();
      case AppPermissionKind.batteryOptimization:
        return Permission.ignoreBatteryOptimizations.request();
      case AppPermissionKind.calendar:
        return Permission.calendarFullAccess.request();
      case AppPermissionKind.bandDeviceManagement:
        return await BandSyncService.requestPermission()
            ? PermissionStatus.granted
            : PermissionStatus.denied;
      case AppPermissionKind.usageStats ||
            AppPermissionKind.exactAlarm ||
            AppPermissionKind.liveUpdates:
        return status(permission);
    }
  }

  Future<bool> _openPermissionSettings(AppPermissionKind permission) async {
    switch (permission) {
      case AppPermissionKind.usageStats:
        await ScreenTimeService.openSettings();
        return true;
      case AppPermissionKind.exactAlarm:
        try {
          await _platformChannel.invokeMethod<void>('openExactAlarmSettings');
          return true;
        } on PlatformException {
          return openAppSettings();
        }
      case AppPermissionKind.batteryOptimization:
        try {
          await _platformChannel.invokeMethod<void>(
            'openBatteryOptimizationSettings',
          );
          return true;
        } on PlatformException {
          return openAppSettings();
        }
      case AppPermissionKind.liveUpdates:
        try {
          return await _platformChannel.invokeMethod<bool>(
                'openLiveUpdatesSettings',
              ) ??
              false;
        } on PlatformException {
          return openAppSettings();
        }
      default:
        return openAppSettings();
    }
  }

  Future<bool> _usesManageExternalStorage() async {
    if (!AppPlatform.isAndroid) return false;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt >= 30;
  }

  Future<bool> _showRationale(AppPermissionKind permission) {
    if (_disposed || _rationaleEntry != null) return Future.value(false);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return Future.value(false);

    _rationaleConfirmed = false;
    _rationaleCompleter = Completer<bool>();
    _rationaleEntry = OverlayEntry(
      builder: (context) => PermissionRationaleBanner(
        permission: permission,
        proceeding: _rationaleConfirmed,
        onAllow: () => _completeRationale(true),
        onDeny: () => _completeRationale(false),
      ),
    );
    overlay.insert(_rationaleEntry!);
    return _rationaleCompleter!.future;
  }

  void _completeRationale(bool confirmed) {
    final completer = _rationaleCompleter;
    if (completer == null || completer.isCompleted) return;
    _rationaleConfirmed = confirmed;
    _rationaleEntry?.markNeedsBuild();
    completer.complete(confirmed);
  }

  void _hideRationale() {
    _rationaleEntry?.remove();
    _rationaleEntry = null;
    _rationaleCompleter = null;
    _rationaleConfirmed = false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final rationaleCompleter = _rationaleCompleter;
    if (rationaleCompleter != null && !rationaleCompleter.isCompleted) {
      rationaleCompleter.complete(false);
    }
    _hideRationale();
    final completer = _resumeCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}

class PermissionRationaleBanner extends StatelessWidget {
  const PermissionRationaleBanner({
    super.key,
    required this.permission,
    required this.proceeding,
    required this.onAllow,
    required this.onDeny,
  });

  final AppPermissionKind permission;
  final bool proceeding;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 12,
      right: 12,
      child: SafeArea(
        child: Material(
          elevation: 8,
          color: colorScheme.surfaceContainerHigh,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.security_outlined,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            proceeding
                                ? '正在打开“${permission.label}”权限'
                                : '需要“${permission.label}”权限',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            proceeding
                                ? '请在接下来的系统页面中完成授权。'
                                : permission.rationale,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    if (proceeding) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                if (!proceeding) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: onDeny,
                        child: const Text('暂不允许'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: onAllow,
                        child: const Text('允许并继续'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
