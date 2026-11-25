import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/app_platform.dart';
import '../utils/time_utils.dart';

/// Reads basic device environment information (local time, timezone, locale,
/// platform) and, when authorized, the user's current geographic location.
class AiDeviceContextService {
  static const MethodChannel _channel = MethodChannel(
    'com.math_quiz_app/device_context',
  );

  static bool get supportsNativeLocation =>
      !kIsWeb &&
      (AppPlatform.isAndroid || AppPlatform.isIOS || AppPlatform.isMacOS);

  static Future<PermissionStatus> getLocationPermissionStatus() async {
    if (!supportsNativeLocation) return PermissionStatus.denied;
    if (AppPlatform.isMacOS) {
      try {
        final raw = await _channel.invokeMethod<String>(
          'getLocationPermissionStatus',
        );
        return _parsePermissionStatus(raw);
      } on PlatformException {
        return PermissionStatus.denied;
      } on MissingPluginException {
        return PermissionStatus.denied;
      }
    }
    try {
      return await Permission.locationWhenInUse.status;
    } catch (_) {
      return PermissionStatus.denied;
    }
  }

  static Future<PermissionStatus> requestLocationPermission() async {
    if (!supportsNativeLocation) return PermissionStatus.denied;
    if (AppPlatform.isMacOS) {
      try {
        final raw = await _channel.invokeMethod<String>(
          'requestLocationPermission',
        );
        return _parsePermissionStatus(raw);
      } on PlatformException {
        return PermissionStatus.denied;
      } on MissingPluginException {
        return PermissionStatus.denied;
      }
    }
    try {
      return await Permission.locationWhenInUse.request();
    } catch (_) {
      return PermissionStatus.denied;
    }
  }

  static PermissionStatus _parsePermissionStatus(String? raw) => switch (raw) {
    'granted' ||
    'authorized' ||
    'authorizedAlways' ||
    'authorizedWhenInUse' => PermissionStatus.granted,
    'limited' => PermissionStatus.limited,
    'restricted' => PermissionStatus.restricted,
    'permanentlyDenied' ||
    'deniedForever' => PermissionStatus.permanentlyDenied,
    _ => PermissionStatus.denied,
  };

  static Future<Map<String, dynamic>> readDeviceContext({
    bool includeLocation = true,
    DateTime? nowOverride,
    Future<PermissionStatus> Function()? requestPermission,
  }) async {
    final current = nowOverride ?? DateTime.now();
    final offset = current.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absMinutes = offset.inMinutes.abs();
    final hours = (absMinutes ~/ 60).toString().padLeft(2, '0');
    final mins = (absMinutes % 60).toString().padLeft(2, '0');
    String two(int n) => n.toString().padLeft(2, '0');

    final result = <String, dynamic>{
      'ok': true,
      'local_time':
          '${current.year}-${two(current.month)}-${two(current.day)} '
          '${two(current.hour)}:${two(current.minute)}:${two(current.second)}',
      'iso_time': current.toIso8601String(),
      'weekday': AppTimeFormats.weekdayLabel(current),
      'timezone_name': current.timeZoneName,
      'timezone_offset': '$sign$hours:$mins',
      'timezone_offset_minutes': offset.inMinutes,
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      'platform': _platformName(),
    };

    if (!includeLocation) return result;

    if (!supportsNativeLocation) {
      result['location'] = {
        'supported': false,
        'authorized': false,
        'message': '当前平台不支持读取设备定位，仅提供时区与时间信息。',
      };
      return result;
    }

    var status = await getLocationPermissionStatus();
    if (!status.isGranted && !status.isLimited && requestPermission != null) {
      status = await requestPermission();
    }

    if (!status.isGranted && !status.isLimited) {
      result['location'] = {
        'supported': true,
        'authorized': false,
        'permission_status': status.name,
        'message': status.isPermanentlyDenied
            ? '位置权限已被永久拒绝，请在系统设置或应用「权限管理」中开启位置权限。'
            : '尚未授权位置权限，可在「AI 助手设置」或「权限管理」中提前授权。',
      };
      return result;
    }

    try {
      final rawLocation = await _channel.invokeMapMethod<String, dynamic>(
        'getLocation',
      );
      if (rawLocation == null || rawLocation.isEmpty) {
        result['location'] = {
          'supported': true,
          'authorized': true,
          'available': false,
          'message': '已授权位置权限，但暂未获取到有效定位（请检查系统定位开关或信号）。',
        };
        return result;
      }
      result['location'] = {
        'supported': true,
        'authorized': true,
        'available': true,
        ...rawLocation,
      };
    } on PlatformException catch (e) {
      result['location'] = {
        'supported': true,
        'authorized': true,
        'available': false,
        'message': e.message ?? '获取设备位置失败。',
      };
    } on MissingPluginException {
      result['location'] = {
        'supported': false,
        'authorized': false,
        'message': '当前运行环境未实现原生定位通道。',
      };
    }

    return result;
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    if (AppPlatform.isAndroid) return 'android';
    if (AppPlatform.isIOS) return 'ios';
    if (AppPlatform.isMacOS) return 'macos';
    if (AppPlatform.isWindows) return 'windows';
    if (AppPlatform.isLinux) return 'linux';
    return 'unknown';
  }
}
