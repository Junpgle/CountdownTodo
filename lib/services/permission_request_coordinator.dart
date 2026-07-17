import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    final prefs = await SharedPreferences.getInstance();
    final agreedKey = 'permission_agreed_${permission.name}';
    final hasAgreed = prefs.getBool(agreedKey) ?? false;

    if ((previousStatus.isGranted || previousStatus.isLimited) && hasAgreed) {
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

    await prefs.setBool(agreedKey, true);

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
    try {
      switch (permission) {
        case AppPermissionKind.notification:
          return await Permission.notification.status;
        case AppPermissionKind.storage:
          if (AppPlatform.isAndroid) {
            final storage = await Permission.storage.status;
            if (await _usesManageExternalStorage()) {
              final managed = await Permission.manageExternalStorage.status;
              return managed.isGranted ? PermissionStatus.granted : managed;
            }
            return storage;
          }
          return await Permission.storage.status;
        case AppPermissionKind.usageStats:
          return await ScreenTimeService.checkPermission()
              ? PermissionStatus.granted
              : PermissionStatus.denied;
        case AppPermissionKind.requestInstall:
          return await Permission.requestInstallPackages.status;
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
          return await Permission.ignoreBatteryOptimizations.status;
        case AppPermissionKind.calendar:
          return await Permission.calendarFullAccess.status;
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
    } catch (_) {
      return PermissionStatus.granted;
    }
  }

  Future<PermissionStatus> _requestPermission(
      AppPermissionKind permission) async {
    try {
      switch (permission) {
        case AppPermissionKind.notification:
          return await Permission.notification.request();
        case AppPermissionKind.storage:
          if (AppPlatform.isAndroid && await _usesManageExternalStorage()) {
            return await Permission.manageExternalStorage.request();
          }
          return await Permission.storage.request();
        case AppPermissionKind.requestInstall:
          return await Permission.requestInstallPackages.request();
        case AppPermissionKind.batteryOptimization:
          return await Permission.ignoreBatteryOptimizations.request();
        case AppPermissionKind.calendar:
          return await Permission.calendarFullAccess.request();
        case AppPermissionKind.bandDeviceManagement:
          return await BandSyncService.requestPermission()
              ? PermissionStatus.granted
              : PermissionStatus.denied;
        case AppPermissionKind.usageStats ||
              AppPermissionKind.exactAlarm ||
              AppPermissionKind.liveUpdates:
          return status(permission);
      }
    } catch (_) {
      return PermissionStatus.granted;
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
      bottom: 16,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, 40 * (1 - value)),
                    child: Opacity(
                      opacity: value.clamp(0.0, 1.0),
                      child: child,
                    ),
                  );
                },
                child: Material(
                  elevation: 16,
                  color: colorScheme.surface,
                  shadowColor: colorScheme.shadow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primaryContainer.withValues(alpha: 0.4),
                          colorScheme.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      colorScheme.primary,
                                      colorScheme.tertiary,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorScheme.primary
                                          .withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.security_rounded,
                                  color: colorScheme.onPrimary,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 16),
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
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      proceeding
                                          ? '请在接下来的系统页面中完成授权。'
                                          : permission.rationale,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            height: 1.5,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (proceeding) ...[
                            const SizedBox(height: 20),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                backgroundColor: colorScheme.primaryContainer,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                          if (!proceeding) ...[
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: onDeny,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    '暂不允许',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: onAllow,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    '允许并继续',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
