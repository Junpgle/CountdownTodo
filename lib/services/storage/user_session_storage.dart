import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../api_service.dart';
import '../background_notification_service.dart';
import '../database_helper.dart';
import '../../utils/app_platform.dart';
import 'storage_key_scope.dart';

/// Immutable identity captured by an asynchronous operation.
///
/// A username alone is not enough: the same account can be logged out and
/// back in while an older request is still in flight.  The revision and user
/// id let callers reject that stale operation before it reads or writes data.
class UserSessionSnapshot {
  const UserSessionSnapshot({
    required this.username,
    required this.userId,
    required this.revision,
  });

  final String username;
  final int userId;
  final int revision;
}

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
  static int _sessionRevision = 0;

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
    _sessionRevision++;
    final prefs = await _prefs;
    await prefs.setString(_currentUser, username);
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_authToken, token);
      ApiService.setToken(token);
    } else {
      await prefs.remove(_authToken);
      ApiService.setToken('');
    }
    await DatabaseHelper.instance.closeDatabase();
  }

  static Future<String?> getLoginSession() async {
    final prefs = await _prefs;
    await restoreAuthToken(prefs: prefs);
    return prefs.getString(_currentUser);
  }

  static Future<String?> restoreAuthToken({SharedPreferences? prefs}) async {
    final storage = prefs ?? await _prefs;
    final token = storage.getString(_authToken);
    ApiService.setToken(token ?? '');
    return token;
  }

  static Future<void> clearLoginSession() async {
    _sessionRevision++;
    final prefs = await _prefs;
    final username = prefs.getString(_currentUser);
    await prefs.remove(_currentUser);
    await prefs.remove('current_user_id');
    await prefs.remove(_scopedKey(_lastScreenTimeSync, username));
    await prefs.remove(_scopedKey(_screenTimeCache, username));
    await prefs.remove(_scopedKey(_screenTimeHistory, username));
    await prefs.remove(_scopedKey(_localScreenTime, username));
    await prefs.remove(_authToken);
    ApiService.setToken('');
    ApiService.currentUserId = 0;
    unawaited(
      BackgroundNotificationService.stopNotificationPoll().catchError((_) {}),
    );
    await DatabaseHelper.instance.closeDatabase();
  }

  /// Captures the currently authenticated account for a long-running task.
  /// Returns null when the requested account is no longer the active account.
  static Future<UserSessionSnapshot?> captureSession(String username) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) return null;

    final prefs = await _prefs;
    final currentUsername = prefs.getString(_currentUser)?.trim();
    final userId = prefs.getInt('current_user_id');
    if (currentUsername != normalizedUsername ||
        userId == null ||
        userId <= 0) {
      return null;
    }
    return UserSessionSnapshot(
      username: normalizedUsername,
      userId: userId,
      revision: _sessionRevision,
    );
  }

  static Future<bool> isCurrentSession(UserSessionSnapshot snapshot) async {
    if (_sessionRevision != snapshot.revision) return false;
    final prefs = await _prefs;
    return prefs.getString(_currentUser)?.trim() == snapshot.username &&
        prefs.getInt('current_user_id') == snapshot.userId;
  }

  static Future<void> ensureCurrentSession(
    UserSessionSnapshot snapshot,
  ) async {
    if (!await isCurrentSession(snapshot)) {
      throw StateError('账户已切换，已取消旧账户异步操作');
    }
  }

  static Future<void> ensureCurrentUsername(String username) async {
    final normalizedUsername = username.trim();
    final prefs = await _prefs;
    if (normalizedUsername.isEmpty ||
        prefs.getString(_currentUser)?.trim() != normalizedUsername) {
      throw StateError('账户已切换，已取消旧账户数据操作');
    }
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
    final accountDeviceKey = StorageKeyScope.scoped(_deviceId, username);
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
      } else if (AppPlatform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        model = "${androidInfo.manufacturer} ${androidInfo.model}";
        final shortestSide = WidgetsBinding.instance.platformDispatcher.views
                .first.physicalSize.shortestSide /
            WidgetsBinding
                .instance.platformDispatcher.views.first.devicePixelRatio;
        type = shortestSide > 600 ? "Tablet" : "Phone";
      } else if (AppPlatform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        model = iosInfo.utsname.machine;
        type =
            iosInfo.model.toLowerCase().contains("ipad") ? "Tablet" : "Phone";
      } else if (AppPlatform.isDesktop) {
        model = AppPlatform.operatingSystem;
        type = "PC";
      }
    } catch (e) {
      debugPrint("获取设备型号失败: $e");
    }

    return "$model ($type)";
  }

  static String _scopedKey(String baseKey, String? username) {
    return StorageKeyScope.scoped(baseKey, username);
  }
}
