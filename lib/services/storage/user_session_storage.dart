import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../api_service.dart';
import '../background_notification_service.dart';
import '../database_helper.dart';

class UserSessionStorage {
  const UserSessionStorage._();

  static const String _users = "users_data";
  static const String _currentUser = "current_login_user";
  static const String _authToken = "auth_session_token";
  static const String _deviceId = "app_device_uuid";
  static const String _lastScreenTimeSync = "last_screen_time_sync";
  static const String _screenTimeCache = "screen_time_cache";
  static const String _screenTimeHistory = "screen_time_history";
  static const String _localScreenTime = "local_screen_time_pending_upload";

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<String?> getCurrentUsername() async {
    final prefs = await _prefs;
    return prefs.getString(_currentUser);
  }

  static Future<bool> register(String username, String password) async {
    final prefs = await _prefs;
    Map<String, dynamic> users = {};
    final usersJson = prefs.getString(_users);
    if (usersJson != null) users = jsonDecode(usersJson);
    if (users.containsKey(username)) return false;
    users[username] = password;
    await prefs.setString(_users, jsonEncode(users));
    return true;
  }

  static Future<bool> login(String username, String password) async {
    final prefs = await _prefs;
    final usersJson = prefs.getString(_users);
    if (usersJson == null) return false;
    final Map<String, dynamic> users = jsonDecode(usersJson);
    return users.containsKey(username) && users[username] == password;
  }

  static Future<void> saveLoginSession(String username, {String? token}) async {
    final prefs = await _prefs;
    await prefs.setString(_currentUser, username);
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_authToken, token);
      ApiService.setToken(token);
    }
    await DatabaseHelper.instance.closeDatabase();
  }

  static Future<String?> getLoginSession() async {
    final prefs = await _prefs;
    final token = prefs.getString(_authToken);
    if (token != null && token.isNotEmpty) {
      ApiService.setToken(token);
    }
    return prefs.getString(_currentUser);
  }

  static Future<void> clearLoginSession() async {
    final prefs = await _prefs;
    final username = prefs.getString(_currentUser);
    await prefs.remove(_currentUser);
    await prefs.remove(_scopedKey(_lastScreenTimeSync, username));
    await prefs.remove(_scopedKey(_screenTimeCache, username));
    await prefs.remove(_scopedKey(_screenTimeHistory, username));
    await prefs.remove(_scopedKey(_localScreenTime, username));
    await prefs.remove(_authToken);
    ApiService.setToken('');
    unawaited(BackgroundNotificationService.stopNotificationPoll());
    await DatabaseHelper.instance.closeDatabase();
  }

  static Future<String> getDeviceId() async {
    final prefs = await _prefs;
    final username = prefs.getString(_currentUser) ?? 'default';
    return _getUniqueDeviceId(username);
  }

  static Future<String> getDeviceIdForUser(String username) =>
      _getUniqueDeviceId(username);

  static Future<String> getDeviceFriendlyName() => _getDetailedDeviceName();

  static Future<String> _getUniqueDeviceId(String username) async {
    final prefs = await _prefs;
    final accountDeviceKey = "${_deviceId}_$username";
    var deviceId = prefs.getString(accountDeviceKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(accountDeviceKey, deviceId);
    }
    return deviceId;
  }

  static Future<String> _getDetailedDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    var model = "Unknown Device";
    var type = "Device";

    try {
      if (kIsWeb) {
        model = "Web Browser";
        type = "PC";
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        model = "${androidInfo.manufacturer} ${androidInfo.model}";
        final shortestSide = WidgetsBinding.instance.platformDispatcher.views
                .first.physicalSize.shortestSide /
            WidgetsBinding
                .instance.platformDispatcher.views.first.devicePixelRatio;
        type = shortestSide > 600 ? "Tablet" : "Phone";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        model = iosInfo.utsname.machine;
        type =
            iosInfo.model.toLowerCase().contains("ipad") ? "Tablet" : "Phone";
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        model = Platform.operatingSystem;
        type = "PC";
      }
    } catch (e) {
      debugPrint("获取设备型号失败: $e");
    }

    return "$model ($type)";
  }

  static String _scopedKey(String baseKey, String? username) {
    if (username == null || username.isEmpty) return baseKey;
    return "${baseKey}_$username";
  }
}
