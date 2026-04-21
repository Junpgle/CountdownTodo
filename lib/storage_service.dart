import 'dart:convert';
import 'dart:io';
import 'package:CountDownTodo/services/pomodoro_sync_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'models.dart';


import 'services/api_service.dart';
import 'services/band_sync_service.dart';
import 'services/pomodoro_service.dart';
import 'services/database_helper.dart'; // 🚀 引入 Uni-Sync 新引擎

class StorageService {
  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get prefs async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  static String? _lastRecurrenceCheckDate;
  static final Map<String, bool> _recurrenceCheckCache = {};

  // --- 常量定义 ---
  static const String KEY_USERS = "users_data";
  static const String KEY_LEADERBOARD = "leaderboard_data";
  static const String KEY_SETTINGS = "quiz_settings";
  static const String KEY_CURRENT_USER = "current_login_user";
  static const String KEY_TODOS = "user_todos";
  static const String KEY_TODO_GROUPS = "user_todo_groups";
  static const String KEY_COUNTDOWNS = "user_countdowns";
  static const String KEY_SCREEN_TIME_CACHE = "screen_time_cache";
  static const String KEY_LAST_SCREEN_TIME_SYNC = "last_screen_time_sync";
  static const String KEY_SCREEN_TIME_HISTORY = "screen_time_history";
  static const String KEY_APP_MAPPINGS = "app_category_mappings";
  static const String KEY_LAST_MAPPINGS_SYNC = "last_mappings_sync";
  static const String KEY_AUTH_TOKEN = "auth_session_token";
  static const String KEY_DEVICE_ID = "app_device_uuid";
  static const String KEY_SYNC_INTERVAL = "app_sync_interval";
  static const String KEY_THEME_MODE = "app_theme_mode";
  static const String KEY_LAST_AUTO_SYNC = "last_auto_sync_time";
  static const String KEY_SEMESTER_PROGRESS_ENABLED =
      "semester_progress_enabled";
  static const String KEY_SEMESTER_START = "semester_start_date";
  static const String KEY_SEMESTER_END = "semester_end_date";
  static const String KEY_TIME_LOGS = "user_time_logs";
  static const String KEY_SERVER_CHOICE = "app_server_choice";
  static const String KEY_PRIVACY_AGREED = "privacy_policy_agreed";
  static const String KEY_PRIVACY_DATE = "privacy_policy_date";
  static const String KEY_PRIVACY_CACHED_VERSION =
      "privacy_policy_cached_version";
  static const String KEY_PRIVACY_CACHE_TIME = "privacy_policy_cache_time";
  static const String PRIVACY_RAW_URL =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';
  static const Duration PRIVACY_CACHE_DURATION = Duration(hours: 1);

  static const String KEY_LOCAL_SCREEN_TIME =
      "local_screen_time_pending_upload";

  static const String KEY_LLM_RETRY_COUNT = "llm_retry_count";
  static const String KEY_PENDING_TODO_CONFIRM = "pending_todo_confirm";
  static const String KEY_WALLPAPER_PROVIDER = "app_wallpaper_provider";
  static const String KEY_WALLPAPER_IMAGE_FORMAT = "app_wallpaper_image_format";
  static const String KEY_WALLPAPER_INDEX = "app_wallpaper_index";
  static const String KEY_WALLPAPER_MKT = "app_wallpaper_mkt";
  static const String KEY_WALLPAPER_RESOLUTION = "app_wallpaper_resolution";

  // Notification settings keys
  static const String KEY_NOTIFY_LIVE_ENABLED = "notify_live_activity_enabled";
  static const String KEY_NOTIFY_NORMAL_ENABLED = "notify_normal_enabled";
  static const String KEY_NOTIFY_COURSE_ENABLED = "notify_course_enabled";
  static const String KEY_NOTIFY_QUIZ_ENABLED = "notify_quiz_enabled";
  static const String KEY_NOTIFY_TODO_SUMMARY_ENABLED =
      "notify_todo_summary_enabled";
  static const String KEY_NOTIFY_APP_UPDATES_ENABLED =
      "notify_app_updates_enabled";
  static const String KEY_TODO_FOLDERS_INLINE = "todo_folders_inline";
  static const String KEY_NOTIFY_SPECIAL_TODO_ENABLED =
      "notify_special_todo_enabled";
  static const String KEY_NOTIFY_POMODORO_ENABLED = "notify_pomodoro_enabled";
  static const String KEY_NOTIFY_TODO_RECOGNIZE_ENABLED =
      "notify_todo_recognize_enabled";
  static const String KEY_NOTIFY_POMODORO_END_ENABLED =
      "notify_pomodoro_end_enabled";
  static const String KEY_NOTIFY_TODO_LIVE_ENABLED = "notify_todo_live_enabled";
  static const String KEY_NOTIFY_REMINDER_ENABLED = "notify_reminder_enabled";
  static const String KEY_COURSE_REMINDER_MINUTES = "course_reminder_minutes";
  static const String KEY_LAST_COURSE_IMPORT_URL = "last_course_import_url";
  static const String KEY_CATEGORY_REMINDER_MINUTES =
      "category_reminder_minutes";
  static const String KEY_WINDOWS_SCHEDULED_REMINDERS =
      "windows_scheduled_reminders";

  static bool _isSyncing = false;
  static bool _isCheckingRecurrence = false; // 🚀 递归锁，防止 getTodos 陷入重复任务检查死循环
  static bool _hasInitedFTS = false;
  static ValueNotifier<String> themeNotifier = ValueNotifier('system');

  /// 🚀 Uni-Sync: 全局数据刷新通知器
  static final ValueNotifier<int> dataRefreshNotifier = ValueNotifier(0);
  static void triggerRefresh() => dataRefreshNotifier.value++;

  // ==========================================
  // 🛡️ 设备信息与标识管理 (解决未知设备问题)
  // ==========================================

  /// 获取设备唯一 UUID (用于后端同步过滤)
  static Future<String> _getUniqueDeviceId(String username) async {
    final prefs = await StorageService.prefs;
    String accountDeviceKey = "${KEY_DEVICE_ID}_$username";
    String? deviceId = prefs.getString(accountDeviceKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(accountDeviceKey, deviceId);
    }
    return deviceId;
  }

  static Future<String> getDeviceFriendlyName() async =>
      _getDetailedDeviceName();

  /// 核心：获取"人话"版的设备型号与类型 (手机/平板/PC)
  static Future<String> _getDetailedDeviceName() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String model = "Unknown Device";
    String type = "Device";

    try {
      if (kIsWeb) {
        model = "Web Browser";
        type = "PC";
      } else if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        model = "${androidInfo.manufacturer} ${androidInfo.model}";
        // 平板判断：最短边大于 600dp 通常认为是平板
        final double shortestSide = WidgetsBinding.instance.platformDispatcher
                .views.first.physicalSize.shortestSide /
            WidgetsBinding
                .instance.platformDispatcher.views.first.devicePixelRatio;
        type = shortestSide > 600 ? "Tablet" : "Phone";
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        model = iosInfo.utsname.machine ?? "iPhone";
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

  static Future<String> getDeviceId() async {
    final prefs = await StorageService.prefs;
    final username = prefs.getString(KEY_CURRENT_USER) ?? 'default';
    return _getUniqueDeviceId(username);
  }

  // ==========================================
  // 基础配置与用户系统
  // ==========================================
  static Future<void> initTheme() async {
    final prefs = await StorageService.prefs;
    themeNotifier.value = prefs.getString(KEY_THEME_MODE) ?? 'system';
  }

  static Future<bool> register(String username, String password) async {
    final prefs = await StorageService.prefs;
    Map<String, dynamic> users = {};
    String? usersJson = prefs.getString(KEY_USERS);
    if (usersJson != null) users = jsonDecode(usersJson);
    if (users.containsKey(username)) return false;
    users[username] = password;
    await prefs.setString(KEY_USERS, jsonEncode(users));
    return true;
  }

  static Future<bool> login(String username, String password) async {
    final prefs = await StorageService.prefs;
    String? usersJson = prefs.getString(KEY_USERS);
    if (usersJson == null) return false;
    Map<String, dynamic> users = jsonDecode(usersJson);
    return users.containsKey(username) && users[username] == password;
  }

  static Future<void> saveLoginSession(String username, {String? token}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_CURRENT_USER, username);
    if (token != null && token.isNotEmpty) {
      await prefs.setString(KEY_AUTH_TOKEN, token);
      ApiService.setToken(token);
    }
  }

  static Future<String?> getLoginSession() async {
    final prefs = await StorageService.prefs;
    String? token = prefs.getString(KEY_AUTH_TOKEN);
    if (token != null && token.isNotEmpty) {
      ApiService.setToken(token);
    }
    return prefs.getString(KEY_CURRENT_USER);
  }

  static Future<void> clearLoginSession() async {
    final prefs = await StorageService.prefs;
    await prefs.remove(KEY_CURRENT_USER);
    await prefs.remove(KEY_LAST_SCREEN_TIME_SYNC);
    await prefs.remove(KEY_AUTH_TOKEN);
    ApiService.setToken('');
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(KEY_SETTINGS, jsonEncode(settings));
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await StorageService.prefs;
    String? jsonStr = prefs.getString(KEY_SETTINGS);
    if (jsonStr != null) return Map<String, dynamic>.from(jsonDecode(jsonStr));
    return {
      'operators': ['+', '-'],
      'min_num1': 0,
      'max_num1': 50,
      'min_num2': 0,
      'max_num2': 50,
      'max_result': 100,
    };
  }

  static Future<void> saveWindowsScheduledReminders(
      List<Map<String, dynamic>> reminders) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(
        KEY_WINDOWS_SCHEDULED_REMINDERS, jsonEncode(reminders));
  }

  static Future<List<Map<String, dynamic>>>
      getWindowsScheduledReminders() async {
    final prefs = await StorageService.prefs;
    String? jsonStr = prefs.getString(KEY_WINDOWS_SCHEDULED_REMINDERS);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      debugPrint("解析 Windows 预约提醒失败: $e");
      return [];
    }
  }

  static Future<void> savePomodoroTags(
      String username, List<Map<String, dynamic>> tags) async {
    final prefs = await StorageService.prefs;
    await prefs.setString("pomodoro_tags_$username", jsonEncode(tags));
  }

  // ==========================================
  // 测验历史与排行榜
  // ==========================================
  static Future<void> saveHistory(
      String username, int score, int duration, String details) async {
    final prefs = await SharedPreferences.getInstance();
    String key = "history_$username";
    List<String> history = prefs.getStringList(key) ?? [];
    Map<String, dynamic> recordMap = {
      'date': DateTime.now().toIso8601String(),
      'score': score,
      'duration': duration,
      'details': details
    };
    history.insert(0, jsonEncode(recordMap));
    await prefs.setStringList(key, history);
  }

  static Future<List<String>> getHistory(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList("history_$username") ?? [];
    return rawList.map((item) {
      try {
        var map = jsonDecode(item);
        if (map is Map) {
          String timeStr = DateFormat('yyyy-MM-dd HH:mm:ss')
              .format(DateTime.parse(map['date']));
          return "时间: $timeStr\n得分: ${map['score']}\n用时: ${map['duration']}秒\n详情:\n${map['details']}\n-----------------";
        }
        return item;
      } catch (e) {
        return item;
      }
    }).toList();
  }

  static Future<Map<String, dynamic>> getMathStats(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList("history_$username") ?? [];
    int totalQuestions = 0, totalCorrect = 0, bestTime = 999999, todayCount = 0;
    bool hasPerfectScore = false;
    DateTime now = DateTime.now();
    for (var item in rawList) {
      try {
        var map = jsonDecode(item);
        int score = map['score'], duration = map['duration'];
        if (map['date'] != null) {
          DateTime date = DateTime.parse(map['date']);
          if (date.year == now.year &&
              date.month == now.month &&
              date.day == now.day) todayCount++;
        }
        totalQuestions += 10;
        totalCorrect += (score ~/ 10);
        if (score == 100) {
          hasPerfectScore = true;
          if (duration < bestTime) bestTime = duration;
        }
      } catch (e) {
        RegExp scoreReg = RegExp(r"得分: (\d+)");
        var match = scoreReg.firstMatch(item);
        if (match != null) {
          int score = int.parse(match.group(1)!);
          totalQuestions += 10;
          totalCorrect += (score ~/ 10);
        }
      }
    }
    double accuracy =
        totalQuestions == 0 ? 0.0 : (totalCorrect / totalQuestions);
    return {
      'accuracy': accuracy,
      'bestTime': hasPerfectScore ? bestTime : null,
      'todayCount': todayCount
    };
  }

  static Future<void> updateLeaderboard(
      String username, int score, int duration) async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> list = [];
    String? jsonStr = prefs.getString(KEY_LEADERBOARD);
    if (jsonStr != null) list = jsonDecode(jsonStr);
    list.add({'username': username, 'score': score, 'time': duration});
    list.sort((a, b) {
      if (a['score'] != b['score']) return b['score'].compareTo(a['score']);
      return a['time'].compareTo(b['time']);
    });
    if (list.length > 10) list = list.sublist(0, 10);
    await prefs.setString(KEY_LEADERBOARD, jsonEncode(list));
    syncData(username);
  }

  static Future<List<Map<String, dynamic>>> getLeaderboard() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(KEY_LEADERBOARD);
    if (jsonStr == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
  }

  // ==========================================
  // 倒计时 (Countdowns)
  // ==========================================
  static Future<void> saveCountdowns(String username, List<CountdownItem> items,
      {bool sync = true, bool isSyncSource = false}) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, CountdownItem> dedupeMap = {};
    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (var item in dedupeMap.values) {
      if (!isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'countdowns',
          'target_uuid': item.id,
          'data_json': jsonEncode(item.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0
        });
      }

      batch.insert('countdowns', {
        'uuid': item.id,
        'team_uuid': item.teamUuid,
        'team_name': item.teamName,
        'creator_id': item.creatorId,
        'creator_name': item.creatorName,
        'title': item.title,
        'target_time': item.targetDate.millisecondsSinceEpoch,
        'is_deleted': item.isDeleted ? 1 : 0,
        'version': item.version,
        'updated_at': item.updatedAt,
        'created_at': item.createdAt
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);

    List<String> jsonList =
        dedupeMap.values.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_COUNTDOWNS}_$username", jsonList);
    if (sync) Future.microtask(() => syncData(username));
  }

  static Future<List<CountdownItem>> getCountdowns(String username,
      {bool includeDeleted = false}) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;

      // 1. 迁移检查
      final List<Map<String, dynamic>> sqliteCount =
          await db.rawQuery('SELECT COUNT(*) as cnt FROM countdowns');
      if (sqliteCount.first['cnt'] == 0) {
        List<String> legacyJsonList =
            prefs.getStringList("${KEY_COUNTDOWNS}_$username") ?? [];
        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 自动迁移倒数日老数据至 SQLite...");
          List<CountdownItem> legacyData = legacyJsonList
              .map((e) => CountdownItem.fromJson(jsonDecode(e)))
              .toList();
          await saveCountdowns(username, legacyData, sync: false);
        }
      }

      // 2. 从 SQL 读取
      final List<Map<String, dynamic>> maps = await db.query('countdowns',
          where: includeDeleted ? null : 'is_deleted = 0');
      if (maps.isNotEmpty) {
        return maps
            .map((m) => CountdownItem(
                  id: m['uuid'],
                  title: m['title'] ?? '',
                  targetDate: DateTime.fromMillisecondsSinceEpoch(
                      m['target_time']),
                  isDeleted: m['is_deleted'] == 1,
                  version: m['version'] ?? 1,
                  updatedAt: m['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
                  createdAt: m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
                  teamUuid: m['team_uuid'],
                  teamName: m['team_name'],
                  creatorId: m['creator_id'],
                  creatorName: m['creator_name'],
                ))
            .toList();
      }
    } catch (e) {
      debugPrint("⚠️ Countdowns SQL 引擎异常: $e");
    }

    // 逃生通道
    List<String> list =
        prefs.getStringList("${KEY_COUNTDOWNS}_$username") ?? [];
    List<CountdownItem> result = [];
    for (var e in list) {
      try {
        result.add(CountdownItem.fromJson(jsonDecode(e)));
      } catch (_) {}
    }
    return result;
  }

  static Future<void> deleteCountdownGlobally(
      String username, String idToDelete) async {
    List<CountdownItem> localCds = await getCountdowns(username);
    int index = localCds.indexWhere((t) => t.id == idToDelete);
    if (index != -1) {
      localCds[index].isDeleted = true;
      try {
        localCds[index].markAsChanged();
      } catch (_) {
        localCds[index].updatedAt = DateTime.now().millisecondsSinceEpoch;
        localCds[index].version += 1;
      }
      await saveCountdowns(username, localCds, sync: true);
    }
  }

  // ==========================================
  // 待办事项 (Todos)
  // ==========================================
  static Future<void> saveTodos(String username, List<TodoItem> items,
      {bool sync = true, bool isSyncSource = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, TodoItem> dedupeMap = {};

    // 🚀 核心优化：只有在非同步源保存时才清理，防止 saveTodos -> getTodos 循环触发
    if (sync && !isSyncSource) {
      _recurrenceCheckCache.clear();
    }

    for (var item in items) {
      final existing = dedupeMap[item.id];
      if (existing == null || item.updatedAt > existing.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    List<TodoItem> dedupeList = dedupeMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    List<String> jsonList =
        dedupeList.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_TODOS}_$username", jsonList);

    // 🚀 Batch 极速批量写入，彻底解决数据库锁死
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (var item in items) {
      if (!isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todos',
          'target_uuid': item.id,
          'data_json': jsonEncode(item.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0
        });
      }
      batch.insert('todos', {
        'uuid': item.id,
        'content': item.title,
        'remark': item.remark,
        'team_uuid': item.teamUuid,
        'team_name': item.teamName,
        'creator_id': item.creatorId,
        'creator_name': item.creatorName,
        'is_completed': item.isDone ? 1 : 0,
        'is_deleted': item.isDeleted ? 1 : 0,
        'version': item.version,
        'due_date': item.dueDate?.millisecondsSinceEpoch,
        'group_id': item.groupId,
        'created_date': item.createdDate ?? item.createdAt,
        'created_at': item.createdAt,
        'updated_at': item.updatedAt,
        'collab_type': item.collabType,
        'recurrence': item.recurrence.index,
        'custom_interval_days': item.customIntervalDays,
        'recurrence_end_date': item.recurrenceEndDate?.millisecondsSinceEpoch,
        'reminder_minutes': item.reminderMinutes,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);

    if (sync) Future.microtask(() => syncData(username));
    Future.microtask(() => _syncTodosToBand(items));
  }

  static Future<void> _syncTodosToBand(List<TodoItem> items) async {
    if (!BandSyncService.isInitialized || !BandSyncService.isConnected) return;
    try {
      final activeTodos =
          items.where((t) => !t.isDeleted).map((t) => t.toJson()).toList();
      await BandSyncService.syncTodos(activeTodos);
    } catch (_) {}
  }

  /// 🚀 Uni-Sync 4.0 增强：原子化更新单条待办，避免全量读写性能开销
  static Future<void> updateSingleTodo(String username, TodoItem item, {bool sync = true}) async {
    final db = await DatabaseHelper.instance.database;
    
    // 1. 同步更新 SQLite
    await db.insert('todos', {
      'uuid': item.id,
      'content': item.title,
      'remark': item.remark,
      'team_uuid': item.teamUuid,
      'team_name': item.teamName,
      'creator_id': item.creatorId,
      'creator_name': item.creatorName,
      'is_completed': item.isDone ? 1 : 0,
      'is_deleted': item.isDeleted ? 1 : 0,
      'version': item.version,
      'updated_at': item.updatedAt,
      'created_at': item.createdAt,
      'due_date': item.dueDate?.millisecondsSinceEpoch,
      'group_id': item.groupId,
      'created_date': item.createdDate,
      'collab_type': item.collabType,
      'recurrence': item.recurrence.index,
      'custom_interval_days': item.customIntervalDays,
      'recurrence_end_date': item.recurrenceEndDate?.millisecondsSinceEpoch,
      'reminder_minutes': item.reminderMinutes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 2. 补齐 Oplog，确保离线更新能被同步
    await db.insert('op_logs', {
      'op_type': 'UPSERT',
      'target_table': 'todos',
      'target_uuid': item.id,
      'data_json': jsonEncode(item.toJson()),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0
    });

    if (sync) Future.microtask(() => syncData(username));
  }

  static Future<List<TodoItem>> getTodos(String username,
      {bool includeDeleted = false}) async {
    final prefs = await StorageService.prefs;
    // 🚀 Uni-Sync 安全方案：双轨读取 + 逃生通道
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;

      final List<Map<String, dynamic>> sqliteCount = await db.rawQuery('SELECT COUNT(*) as cnt FROM todos');
      if (sqliteCount.first['cnt'] == 0) {
        List<String> legacyJsonList = prefs.getStringList("${KEY_TODOS}_$username") ?? [];
        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 自动迁移老数据至 SQLite...");
          List<Map<String, dynamic>> legacyData = legacyJsonList.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
          await dbHelper.migrateFromPrefs(username, legacyData);
        }
      }

      final List<Map<String, dynamic>> maps = await db.query('todos',
          where: includeDeleted ? null : 'is_deleted IS NOT 1' // 🚀 兼容 0 或 NULL
          );
      if (maps.isNotEmpty) {
        List<TodoItem> todos = maps.map((m) => TodoItem(
          id: m['uuid'],
          title: m['content'] ?? '',
          remark: m['remark'],
          isDone: m['is_completed'] == 1,
          isDeleted: m['is_deleted'] == 1,
          version: m['version'] ?? 1,
          updatedAt: m['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
          createdAt: m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
          // 🚀 核心修复：处理从 TEXT 字段读取出的时间戳字符串
          createdDate: m['created_date'] is String ? int.tryParse(m['created_date']) : m['created_date'] as int?,
          dueDate: m['due_date'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(m['due_date'].toString()) ?? 0) 
              : null,
          teamUuid: m['team_uuid'],
          teamName: m['team_name'],
          creatorId: m['creator_id'],
          creatorName: m['creator_name'],
          groupId: m['group_id'], 
          collabType: m['collab_type'] ?? 0,
          recurrence: RecurrenceType.values[m['recurrence'] as int? ?? 0],
          customIntervalDays: m['custom_interval_days'] as int?,
          recurrenceEndDate: m['recurrence_end_date'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(m['recurrence_end_date'] as int) 
              : null,
          reminderMinutes: m['reminder_minutes'] as int?,
        )).toList();
        return await _handleRecurrenceLogic(username, todos);
      }
    } catch (e) {
      debugPrint("⚠️ SQL 引擎异常，启动逃生通道: $e");
    }

    // 🚀 逃生通道：兜底读取 Prefs
    List<String> list = prefs.getStringList("${KEY_TODOS}_$username") ?? [];
    List<TodoItem> legacyTodos = [];
    for (var e in list) {
      try { legacyTodos.add(TodoItem.fromJson(jsonDecode(e))); } catch (_) {}
    }
    return await _handleRecurrenceLogic(username, legacyTodos);
  }

  /// 🚀 Uni-Sync 4.0: 当被移出团队时，彻底清理本地缓存的相关数据
  static Future<void> clearTeamItems(String teamUuid) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();

    // 1. 删除 Todos
    batch.delete('todos', where: 'team_uuid = ?', whereArgs: [teamUuid]);
    // 2. 删除 Todo Groups
    batch.delete('todo_groups', where: 'team_uuid = ?', whereArgs: [teamUuid]);
    // 3. 删除 Countdowns
    batch.delete('countdowns', where: 'team_uuid = ?', whereArgs: [teamUuid]);

    await batch.commit(noResult: true);
    debugPrint("🧹 已清理团队 $teamUuid 的本地数据");
    triggerRefresh(); // 🚀 触发 UI 刷新
  }

  static Future<List<TodoItem>> _handleRecurrenceLogic(String username, List<TodoItem> todos) async {
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month}-${today.day}';
    
    if (_lastRecurrenceCheckDate != todayKey) {
      _lastRecurrenceCheckDate = todayKey;
      _recurrenceCheckCache.clear();
    }

    final cacheKey = 'recurrence_$username';
    if (_recurrenceCheckCache.containsKey(cacheKey) || _isCheckingRecurrence) return todos;
    
    _isCheckingRecurrence = true;

    try {
      bool needSave = false;
      for (var todo in todos) {
        if (todo.isDeleted || todo.recurrence == RecurrenceType.none) continue;
        if (todo.recurrenceEndDate != null && today.isAfter(todo.recurrenceEndDate!)) continue;

        final DateTime baseLocal = _getRecurrenceBaseDate(todo);
        final DateTime baseDay = DateTime(baseLocal.year, baseLocal.month, baseLocal.day);
        final DateTime todayDay = DateTime(today.year, today.month, today.day);

        if (todo.recurrence == RecurrenceType.daily && todayDay.isAfter(baseDay)) {
          todo.isDone = false;
          _rollRecurrenceDateToToday(todo, today);
          todo.markAsChanged();
          needSave = true;
        } else if (todo.recurrence == RecurrenceType.customDays && todo.customIntervalDays != null && todo.customIntervalDays! > 0) {
          int diffDays = todayDay.difference(baseDay).inDays;
          if (diffDays >= todo.customIntervalDays!) {
            todo.isDone = false;
            int periods = diffDays ~/ todo.customIntervalDays!;
            _rollRecurrenceDateByDays(todo, periods * todo.customIntervalDays!);
            todo.markAsChanged();
            needSave = true;
          }
        }
      }

      if (needSave) {
        debugPrint("🚀 [Recurrence] 发现重复任务需要滚动，正在保存...");
        await saveTodos(username, todos, sync: true);
      }
      _recurrenceCheckCache[cacheKey] = true;
      _isCheckingRecurrence = false;
      return todos;
    } catch (e) {
      debugPrint("❌ [Recurrence] 逻辑异常: $e");
      _isCheckingRecurrence = false;
      return todos;
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime _getRecurrenceBaseDate(TodoItem todo) {
    if (todo.dueDate != null) return todo.dueDate!;
    final int ms = todo.createdDate ?? todo.createdAt;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }

  static void _rollRecurrenceDateToToday(TodoItem todo, DateTime now) {
    if (todo.dueDate != null) {
      todo.dueDate = DateTime(
        now.year,
        now.month,
        now.day,
        todo.dueDate!.hour,
        todo.dueDate!.minute,
        todo.dueDate!.second,
      );
    } else if (todo.createdDate != null) {
      final orig =
          DateTime.fromMillisecondsSinceEpoch(todo.createdDate!, isUtc: true)
              .toLocal();
      todo.createdDate = DateTime(
              now.year, now.month, now.day, orig.hour, orig.minute, orig.second)
          .millisecondsSinceEpoch;
    }
  }

  static void _rollRecurrenceDateByDays(TodoItem todo, int days) {
    if (todo.dueDate != null) {
      todo.dueDate = todo.dueDate!.add(Duration(days: days));
    } else if (todo.createdDate != null) {
      todo.createdDate =
          todo.createdDate! + Duration(days: days).inMilliseconds;
    }
  }

  static Future<bool> deleteTodoGlobally(
      String username, String idToDelete) async {
    List<TodoItem> localTodos = await getTodos(username);
    int index = localTodos.indexWhere((t) => t.id == idToDelete);

    if (index == -1) return false;

    localTodos[index].isDeleted = true;

    try {
      localTodos[index].markAsChanged();
    } catch (_) {
      localTodos[index].updatedAt = DateTime.now().millisecondsSinceEpoch;
      localTodos[index].version += 1;
    }

    await saveTodos(username, localTodos, sync: true);
    return true;
  }

  // ==========================================
  // 📁 待办组 (Todo Groups)
  // ==========================================
  static Future<void> saveTodoGroups(String username, List<TodoGroup> items,
      {bool sync = true, bool isSyncSource = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, TodoGroup> dedupeMap = {};

    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (var item in dedupeMap.values) {
      if (!isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todo_groups',
          'target_uuid': item.id,
          'data_json': jsonEncode(item.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0
        });
      }

      batch.insert('todo_groups', {
        'uuid': item.id,
        'team_uuid': item.teamUuid,
        'team_name': item.teamName,
        'creator_id': item.creatorId,
        'creator_name': item.creatorName,
        'name': item.name,
        'is_expanded': item.isExpanded ? 1 : 0,
        'is_deleted': item.isDeleted ? 1 : 0,
        'version': item.version,
        'updated_at': item.updatedAt,
        'created_at': item.createdAt
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);

    List<String> jsonList =
        dedupeMap.values.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_TODO_GROUPS}_$username", jsonList);
    if (sync) Future.microtask(() => syncData(username));
  }

  static Future<List<TodoGroup>> getTodoGroups(String username,
      {bool includeDeleted = false}) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      final prefs = await SharedPreferences.getInstance();

      // 1. 迁移检查
      final List<Map<String, dynamic>> sqliteCount =
          await db.rawQuery('SELECT COUNT(*) as cnt FROM todo_groups');
      if (sqliteCount.first['cnt'] == 0) {
        List<String> legacyJsonList =
            prefs.getStringList("${KEY_TODO_GROUPS}_$username") ?? [];
        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 自动迁移待办组数据至 SQLite...");
          List<TodoGroup> legacyData = legacyJsonList
              .map((e) => TodoGroup.fromJson(jsonDecode(e)))
              .toList();
          await saveTodoGroups(username, legacyData, sync: false);
        }
      }

      // 2. 从 SQL 读取 (排除逻辑删除)
      final List<Map<String, dynamic>> maps = await db.query('todo_groups',
          where: includeDeleted ? null : 'is_deleted = 0');
      if (maps.isNotEmpty) {
        return maps
            .map((m) => TodoGroup(
                  id: m['uuid'],
                  name: m['name'] ?? '',
                  isExpanded: m['is_expanded'] == 1,
                  isDeleted: m['is_deleted'] == 1,
                  version: m['version'] ?? 1,
                  updatedAt: m['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
                  createdAt: m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
                  teamUuid: m['team_uuid'],
                  teamName: m['team_name'],
                  creatorId: m['creator_id'],
                  creatorName: m['creator_name'],
                ))
            .toList();
      }
    } catch (e) {
      debugPrint("⚠️ TodoGroups SQL 引擎异常: $e");
    }

    // 逃生通道
    final prefs = await StorageService.prefs;
    List<String> list =
        prefs.getStringList("${KEY_TODO_GROUPS}_$username") ?? [];
    List<TodoGroup> result = [];

    for (var e in list) {
      try {
        result.add(TodoGroup.fromJson(jsonDecode(e)));
      } catch (err) {
        debugPrint("Parse TodoGroup Error: $err");
      }
    }
    return result;
  }

  static Future<void> deleteTodoGroupGlobally(
      String username, String idToDelete) async {
    List<TodoGroup> localGroups = await getTodoGroups(username);
    int index = localGroups.indexWhere((t) => t.id == idToDelete);

    if (index != -1) {
      localGroups[index].isDeleted = true;
      localGroups[index].markAsChanged();
      await saveTodoGroups(username, localGroups, sync: true);
    }

    // 同时将组内的待办恢复为未分组状态
    List<TodoItem> allTodos = await getTodos(username);
    bool todoChanged = false;
    for (var t in allTodos) {
      if (t.groupId == idToDelete) {
        t.groupId = null;
        t.markAsChanged();
        todoChanged = true;
      }
    }
    if (todoChanged) {
      await saveTodos(username, allTodos, sync: true);
    }
  }

  // ==========================================
  // 时间日志 (Time Logs)
  // ==========================================
  static Future<void> saveTimeLogs(String username, List<TimeLogItem> items,
      {bool sync = true}) async {
    final prefs = await StorageService.prefs;
    final Map<String, TimeLogItem> dedupeMap = {};

    for (var item in items) {
      final existing = dedupeMap[item.id];
      // LWW 策略：比较 version 和 updatedAt
      if (existing == null ||
          item.version > existing.version ||
          (item.version == existing.version &&
              item.updatedAt > existing.updatedAt)) {
        dedupeMap[item.id] = item;
      }
    }

    List<TimeLogItem> result = dedupeMap.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    List<String> jsonList = result.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_TIME_LOGS}_$username", jsonList);

    if (sync) Future.microtask(() => syncData(username));
  }

  static Future<List<TimeLogItem>> getTimeLogs(String username) async {
    final prefs = await StorageService.prefs;
    List<String> list = prefs.getStringList("${KEY_TIME_LOGS}_$username") ?? [];
    List<TimeLogItem> logs = [];

    for (var e in list) {
      try {
        logs.add(TimeLogItem.fromJson(jsonDecode(e)));
      } catch (err) {
        debugPrint("Parse TimeLog Error: $err");
      }
    }
    return logs;
  }

  static Future<bool> deleteTimeLogGlobally(
      String username, String idToDelete) async {
    List<TimeLogItem> localLogs = await getTimeLogs(username);
    int index = localLogs.indexWhere((t) => t.id == idToDelete);

    if (index == -1) return false;

    localLogs[index].isDeleted = true;
    localLogs[index].markAsChanged();

    await saveTimeLogs(username, localLogs, sync: true);
    return true;
  }

  // ==========================================
  // 屏幕时间与应用映射
  // ==========================================
  static Future<void> saveLocalScreenTime(Map<dynamic, dynamic> stats) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(KEY_LOCAL_SCREEN_TIME, jsonEncode(stats));
  }

  static Future<Map<String, dynamic>> getLocalScreenTimeMap() async {
    final prefs = await StorageService.prefs;
    String? jsonStr = prefs.getString(KEY_LOCAL_SCREEN_TIME);
    if (jsonStr != null) {
      try {
        return jsonDecode(jsonStr);
      } catch (_) {}
    }
    return {};
  }

  static Future<List<dynamic>> getLocalScreenTime() async {
    final map = await getLocalScreenTimeMap();
    return map['apps'] as List<dynamic>? ?? [];
  }

  static Future<void> saveScreenTimeCache(List<dynamic> stats) async {
    if (stats.isEmpty) return;

    final prefs = await StorageService.prefs;
    final now = DateTime.now();
    final String today = DateFormat('yyyy-MM-dd').format(now);

    // 1. 获取已有的历史记录
    String? histStr = prefs.getString(KEY_SCREEN_TIME_HISTORY);
    Map<String, dynamic> history = {};
    if (histStr != null) {
      try {
        history = jsonDecode(histStr);
      } catch (e) {
        debugPrint("解析历史记录失败: $e");
      }
    }

    // 2. 更新历史记录
    // 即使 stats 里混入了旧数据，我们也只将其视为“今日最新快照”存储在 today 键下
    // 如果你想更严格，可以在此处对 stats 进行过滤，确保 e['date'] == today
    history[today] = stats;

    // 3. 维护 14 天滑动窗口 (删除最旧的记录)
    if (history.length > 14) {
      var sortedKeys = history.keys.toList()..sort();
      while (history.length > 14) {
        history.remove(sortedKeys.removeAt(0));
      }
    }

    // 4. 原子化写入本地存储
    await prefs.setString(KEY_SCREEN_TIME_HISTORY, jsonEncode(history));

    // 5. 更新“当前视图快照” (KEY_SCREEN_TIME_CACHE)
    // 🚀 核心修复：只有当最新更新日期确实是今天时，才更新首页显示的 Cache
    // 这样如果凌晨同步了旧数据，首页不会被错误覆盖
    await prefs.setString(KEY_SCREEN_TIME_CACHE, jsonEncode(stats));

    // 更新最后同步成功的时间戳（记录到毫秒）
    await prefs.setInt(KEY_LAST_SCREEN_TIME_SYNC, now.millisecondsSinceEpoch);
  }

  static Future<List<dynamic>> getScreenTimeCache() async {
    final prefs = await StorageService.prefs;

    // 检查缓存是否是今天的
    int? lastSyncMs = prefs.getInt(KEY_LAST_SCREEN_TIME_SYNC);
    if (lastSyncMs != null) {
      DateTime lastSyncDate =
          DateTime.fromMillisecondsSinceEpoch(lastSyncMs).toLocal();
      DateTime now = DateTime.now();

      // 如果缓存日期不是今天，说明缓存已过期，返回空列表触发新的同步
      if (lastSyncDate.year != now.year ||
          lastSyncDate.month != now.month ||
          lastSyncDate.day != now.day) {
        debugPrint("缓存已过期 (日期不匹配)，清理过期数据");
        await prefs.remove(KEY_SCREEN_TIME_CACHE);
        return [];
      }
    }

    String? jsonStr = prefs.getString(KEY_SCREEN_TIME_CACHE);
    if (jsonStr != null) {
      try {
        return jsonDecode(jsonStr);
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  static Future<Map<String, List<dynamic>>> getScreenTimeHistory() async {
    final prefs = await StorageService.prefs;
    String? jsonStr = prefs.getString(KEY_SCREEN_TIME_HISTORY);
    if (jsonStr != null) {
      try {
        Map<String, dynamic> raw = jsonDecode(jsonStr);
        return raw
            .map((key, value) => MapEntry(key, List<dynamic>.from(value)));
      } catch (_) {}
    }
    return {};
  }

  static Future<void> updateLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        KEY_LAST_SCREEN_TIME_SYNC, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    int? timestamp = prefs.getInt(KEY_LAST_SCREEN_TIME_SYNC);
    if (timestamp != null)
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
          .toLocal();
    return null;
  }

  static Future<void> syncAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    int? lastSync = prefs.getInt(KEY_LAST_MAPPINGS_SYNC);
    DateTime now = DateTime.now();
    if (lastSync != null) {
      DateTime lastDate =
          DateTime.fromMillisecondsSinceEpoch(lastSync, isUtc: true).toLocal();
      if (now.difference(lastDate).inDays < 7) return;
    }
    List<dynamic> mappings = await ApiService.fetchAppMappings();
    if (mappings.isNotEmpty) {
      Map<String, String> lookupMap = {};
      for (var item in mappings) {
        String pkg = item['package_name'] ?? '';
        String mapped = item['mapped_name'] ?? '';
        String cat = item['category'] ?? '未分类';
        if (pkg.isNotEmpty) lookupMap[pkg] = cat;
        if (mapped.isNotEmpty) lookupMap[mapped] = cat;
      }
      await prefs.setString(KEY_APP_MAPPINGS, jsonEncode(lookupMap));
      await prefs.setInt(KEY_LAST_MAPPINGS_SYNC, now.millisecondsSinceEpoch);
    }
  }

  static Future<Map<String, String>> getAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(KEY_APP_MAPPINGS);
    if (jsonStr != null) {
      try {
        return Map<String, String>.from(jsonDecode(jsonStr));
      } catch (_) {}
    }
    return {};
  }

  // ==========================================
  // 🚀 核心：增量同步算法 (包含屏幕时间推送)
  // ==========================================

  static Future<void> resetSyncTime(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_sync_time_aliyun_$username');
    await prefs.remove('last_sync_time_cf_$username');
    await prefs.remove('last_sync_time_$username'); // 兼容旧版本
  }

  static Future<Map<String, dynamic>> syncData(
    String username, {
    bool syncTodos = true,
    bool syncCountdowns = true,
    bool forceFullSync = false,
    BuildContext? context,
    bool syncTimeLogs = true,
    bool syncPomodoro = true,
  }) async {
    // 1. 状态锁：防止重复进入
    if (!syncTodos && !syncCountdowns && !syncTimeLogs && !syncPomodoro)
      return {'success': false, 'hasChanges': false};
    if (_isSyncing) return {'success': false, 'hasChanges': false};
    _isSyncing = true;
    bool hasChanges = false;
    List<ConflictInfo> conflicts = [];

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("用户未登录");

      // 2. 环境信息准备
      final String deviceId = await _getUniqueDeviceId(username);
      final String friendlyName = await _getDetailedDeviceName();
      final String serverKey = ApiService.baseUrl == ApiService.aliyunProdUrl ? "aliyun" : "cf";
      final int lastSyncTime = forceFullSync
          ? 0
          : (prefs.getInt('last_sync_time_${serverKey}_$username') ?? 0);

      // 3. 🛡️ 核心修复：基于 op_logs 识别脏数据，不再依赖不可靠的时间戳对比
      final db = await DatabaseHelper.instance.database;
      List<Map<String, dynamic>> dirtyTodos = [];
      List<Map<String, dynamic>> dirtyGroups = [];
      List<Map<String, dynamic>> dirtyCountdowns = [];
      List<Map<String, dynamic>> dirtyTimeLogs = [];

      List<TodoItem> allLocalTodos =
          await getTodos(username, includeDeleted: true);
      List<TodoGroup> allLocalGroups =
          await getTodoGroups(username, includeDeleted: true);
      List<CountdownItem> allLocalCountdowns =
          await getCountdowns(username, includeDeleted: true);
      List<TimeLogItem> allLocalTimeLogs = await getTimeLogs(username);

      final List<Map<String, dynamic>> pendingOps = await db.query('op_logs', where: 'is_synced = 0');
      debugPrint('🔍 [同步流水] 发现 ${pendingOps.length} 条待同步操作');

      for (var op in pendingOps) {
        final table = op['target_table'];
        final data = jsonDecode(op['data_json'] as String);
        if (table == 'todos') {
          data.remove('image_path');
          data.remove('imagePath');
          dirtyTodos.add(data);
        } else if (table == 'todo_groups') {
          dirtyGroups.add(data);
        } else if (table == 'countdowns') {
          dirtyCountdowns.add(data);
        }
      }

      // TimeLogs 暂时保持原有逻辑 (直到迁移至 SQL)
      dirtyTimeLogs = allLocalTimeLogs.where((t) => t.updatedAt > lastSyncTime).map((t) => t.toJson()).toList();

      debugPrint('🔍 [同步判定] lastSyncTime: $lastSyncTime, 本地总任务数: ${allLocalTodos.length}');

      // 4. 读取本机待同步屏幕时间 (改为 Map 结构)
      Map<String, dynamic> localPackage = await getLocalScreenTimeMap();
      List<dynamic> localScreenStats = localPackage['apps'] ?? [];
      String? recordDate = localPackage['date']; // 🚀 从缓存中拿原始日期

      Map<String, dynamic>? screenPayload;
      if (localScreenStats.isNotEmpty) {
        try {
          // 如果没有记录日期（旧版本升级上来），退而求其次用今天
          final String finalDate =
              recordDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

          screenPayload = {
            'device_name': friendlyName,
            'record_date': finalDate,
            'apps': localScreenStats
                .where((e) => e is Map)
                .map((e) => {
                      'app_name': e['app_name']?.toString() ?? 'Unknown',
                      'duration': (e['duration'] is int) ? e['duration'] : 0,
                    })
                .toList(),
          };
          debugPrint(
              "🚀 准备同步本机屏幕时间 ($finalDate): ${localScreenStats.length} 条数据");
        } catch (se) {
          debugPrint("屏幕时间 payload 构造失败: $se");
        }
      } else {
        // null
      }

      // 5. 发起网络同步请求
      final response = await ApiService.postDeltaSync(
        userId: userId,
        lastSyncTime: lastSyncTime,
        deviceId: deviceId,
        todosChanges: dirtyTodos,
        todoGroupsChanges: dirtyGroups,
        countdownsChanges: dirtyCountdowns,
        timeLogsChanges: dirtyTimeLogs,
        screenTime: screenPayload,
      );

      if (response['success'] == true) {
        // 🚀 全部上报成功后，标记 op_logs 为已同步
        await db.update('op_logs', {'is_synced': 1}, where: 'is_synced = 0');
        debugPrint('✅ [同步流水] 已标记记录为已同步');

        // 🚀 处理独立待办完成情况
        final List<dynamic>? indCompletions = response['independent_completions'];
        if (indCompletions != null) {
          final batch = db.batch();
          for (var ic in indCompletions) {
            batch.insert('todo_completions', {
              'todo_uuid': ic['todo_uuid'],
              'user_id': userId,
              'is_completed': ic['is_completed'],
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
        }

        // 🚀 核心修复：清理本地孤立的团队数据 (处理离线被移出团队的情况)
        final List<dynamic>? joinedTeamUuids = response['joined_team_uuids'];
        if (joinedTeamUuids != null) {
          final Set<String> currentTeams = joinedTeamUuids.map((e) => e.toString()).toSet();
          
          // 获取本地所有存在的 team_uuid
          final localTeamRows = await db.rawQuery('SELECT DISTINCT team_uuid FROM todos WHERE team_uuid IS NOT NULL');
          bool teamChanged = false;
          for (var row in localTeamRows) {
            String? tUuid = row['team_uuid']?.toString();
            if (tUuid != null && !currentTeams.contains(tUuid)) {
               debugPrint("🧹 发现孤立团队数据: $tUuid, 正在清理...");
               await clearTeamItems(tUuid);
               hasChanges = true;
               teamChanged = true;
            }
          }

          // 🚀 核心优化：如果发现同步返回的团队列表与本地认知不符，或者刚刚清理了孤立团队，则提示 WS 重新订阅新频道
          if (teamChanged || currentTeams.length != localTeamRows.length) {
            debugPrint("👥 [协同] 团队列表发生变化，请求 WebSocket 刷新订阅...");
            // 利用 resumeSync 内部的逻辑可以触发重连与重新订阅
            Future.microtask(() => PomodoroSyncService.instance.resumeSync());
          }
        }
      } else {
        throw Exception("${response['message'] ?? '同步失败'}");
      }
      
      // 解析服务器返回的实时冲突
      if (response['conflicts'] != null) {
        conflicts = (response['conflicts'] as List).map((c) => ConflictInfo.fromJson(c)).toList();
      }

      // 🛡️ 屏幕时间逻辑优化：上传成功后，务必清理“待上传”缓存
      if (screenPayload != null) {
        await prefs.remove(KEY_LOCAL_SCREEN_TIME);
        debugPrint("✅ 本机屏幕时间上传成功，已清理待上传缓存");
      }

      // 6. 🛡️ 数据合并逻辑 (LWW - Last Write Wins) — O(1) HashMap lookup

      // 合并 Todos
      List<dynamic> serverTodos = response['server_todos'] ?? [];


      final Map<String, int> todosIndexMap = {
        for (var i = 0; i < allLocalTodos.length; i++) allLocalTodos[i].id: i
      };
      for (var raw in serverTodos) {
        TodoItem sItem = TodoItem.fromJson(raw);
        if (todosIndexMap.containsKey(sItem.id)) {
          final idx = todosIndexMap[sItem.id]!;
          final local = allLocalTodos[idx];
          debugPrint('🔄 [合并对比] UUID: ${sItem.id}, Server(V:${sItem.version}, D:${sItem.isDeleted}), Local(V:${local.version}, D:${local.isDeleted})');
          
          if (sItem.isDeleted ||
              sItem.version > local.version ||
              sItem.updatedAt > local.updatedAt) {
            allLocalTodos[idx] = sItem;
            hasChanges = true;
          } else if (sItem.groupId != local.groupId &&
              sItem.updatedAt >= local.updatedAt) {
            // Only accept group_id changes if server item is at least as new
            // as local item, preserving LWW semantics for folder assignments.
            allLocalTodos[idx].groupId = sItem.groupId;
            hasChanges = true;
          }
        } else {
          if (!sItem.isDeleted) {
            todosIndexMap[sItem.id] = allLocalTodos.length;
            allLocalTodos.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 TodoGroups
      List<dynamic> serverGroups = response['server_todo_groups'] ?? [];
      final Map<String, int> groupsIndexMap = {
        for (var i = 0; i < allLocalGroups.length; i++) allLocalGroups[i].id: i
      };
      for (var raw in serverGroups) {
        TodoGroup sItem = TodoGroup.fromJson(raw);
        if (groupsIndexMap.containsKey(sItem.id)) {
          final idx = groupsIndexMap[sItem.id]!;
          if (sItem.isDeleted ||
              sItem.version > allLocalGroups[idx].version ||
              sItem.updatedAt > allLocalGroups[idx].updatedAt) {
            allLocalGroups[idx] = sItem;
            hasChanges = true;
          }
        } else {
          if (!sItem.isDeleted) {
            groupsIndexMap[sItem.id] = allLocalGroups.length;
            allLocalGroups.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 Countdowns
      List<dynamic> serverCountdowns = response['server_countdowns'] ?? [];
      final Map<String, int> countdownsIndexMap = {
        for (var i = 0; i < allLocalCountdowns.length; i++)
          allLocalCountdowns[i].id: i
      };
      for (var raw in serverCountdowns) {
        CountdownItem sItem = CountdownItem.fromJson(raw);
        if (countdownsIndexMap.containsKey(sItem.id)) {
          final idx = countdownsIndexMap[sItem.id]!;
          if (sItem.isDeleted ||
              sItem.version > allLocalCountdowns[idx].version ||
              sItem.updatedAt > allLocalCountdowns[idx].updatedAt) {
            allLocalCountdowns[idx] = sItem;
            hasChanges = true;
          }
        } else {
          if (!sItem.isDeleted) {
            countdownsIndexMap[sItem.id] = allLocalCountdowns.length;
            allLocalCountdowns.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 TimeLogs
      List<dynamic> serverTimeLogs = response['server_time_logs'] ?? [];
      final Map<String, int> timeLogsIndexMap = {
        for (var i = 0; i < allLocalTimeLogs.length; i++)
          allLocalTimeLogs[i].id: i
      };
      for (var raw in serverTimeLogs) {
        TimeLogItem sItem = TimeLogItem.fromJson(raw);
        if (timeLogsIndexMap.containsKey(sItem.id)) {
          final idx = timeLogsIndexMap[sItem.id]!;
          if (sItem.isDeleted ||
              sItem.version > allLocalTimeLogs[idx].version ||
              sItem.updatedAt > allLocalTimeLogs[idx].updatedAt) {
            allLocalTimeLogs[idx] = sItem;
            hasChanges = true;
          }
        } else {
          if (!sItem.isDeleted) {
            timeLogsIndexMap[sItem.id] = allLocalTimeLogs.length;
            allLocalTimeLogs.add(sItem);
            hasChanges = true;
          }
        }
      }
      
      // 合并 Pomodoro (Tags & Records)
      if (syncPomodoro) {
        try {
          // 顺序：拉取标签 -> 上传标签 -> 上传记录 -> 拉取记录
          await PomodoroService.syncTagsFromCloud();
          await PomodoroService.syncTagsToCloud();
          await PomodoroService.syncRecordsToCloud();
          bool pomodoroChanged = await PomodoroService.syncRecordsFromCloud();
          if (pomodoroChanged) hasChanges = true;
        } catch (pe) {
          debugPrint("Pomodoro sync error: $pe");
        }
      }

      // 7. 持久化数据
      if (hasChanges) {
        await saveTodos(username, allLocalTodos, sync: false, isSyncSource: true);
        await saveTodoGroups(username, allLocalGroups, sync: false, isSyncSource: true);
        await saveCountdowns(username, allLocalCountdowns, sync: false, isSyncSource: true);
        await saveTimeLogs(username, allLocalTimeLogs, sync: false);
      }

      // 8. 更新同步水位线
      int newSyncTime =
          response['new_sync_time'] ?? DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('last_sync_time_${serverKey}_$username', newSyncTime);

      // 如果屏幕时间同步成功，可以在这里刷新 UI 用的 Cache 数据（如果后端有返回最新的聚合数据）
      if (response['screen_time_results'] != null) {
        await saveScreenTimeCache(response['screen_time_results']);
      }

      return {'success': true, 'hasChanges': hasChanges, 'conflicts': conflicts};
    } catch (e) {
      debugPrint("syncData error: $e");
      return {'success': false, 'hasChanges': false, 'error': e.toString()};
    } finally {
      _isSyncing = false;
    }
  }

  static Future<bool> syncScreenTimeAlone(
      String username, String deviceName) async {
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId == null) {
      debugPrint("syncScreenTimeAlone: user not logged in");
      return false;
    }

    try {
      final localPackage = await getLocalScreenTimeMap();
      final apps = localPackage['apps'] as List<dynamic>?;
      final date = localPackage['date'] as String?;

      if (apps == null || apps.isEmpty || date == null) {
        debugPrint("syncScreenTimeAlone: no data to upload");
        return false;
      }

      final formattedApps = apps
          .where((e) => e is Map)
          .map((e) => {
                'app_name': e['app_name']?.toString() ?? 'Unknown',
                'duration': (e['duration'] is int) ? e['duration'] : 0,
              })
          .toList();

      final success = await ApiService.uploadScreenTime(
        userId: userId,
        deviceName: deviceName,
        date: date,
        apps: formattedApps,
      );

      if (success) {
        await prefs.remove(KEY_LOCAL_SCREEN_TIME);
        return true;
      } else {
        debugPrint("syncScreenTimeAlone failed");
        return false;
      }
    } catch (e) {
      debugPrint("syncScreenTimeAlone error: $e");
      return false;
    }
  }

  // ==========================================
  // 偏好设置与状态管理
  // ==========================================
  static Future<void> saveAppSetting(String key, dynamic value) async {
    final prefs = await StorageService.prefs;
    if (value is int) await prefs.setInt(key, value);
    if (value is String) await prefs.setString(key, value);
    if (value is bool) await prefs.setBool(key, value);
    if (key == KEY_THEME_MODE) themeNotifier.value = value;
  }

  static Future<int> getSyncInterval() async {
    final prefs = await StorageService.prefs;
    return prefs.getInt(KEY_SYNC_INTERVAL) ?? 0;
  }

  static Future<String> getThemeMode() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(KEY_THEME_MODE) ?? 'system';
  }

  static Future<void> saveServerChoice(String choice) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(KEY_SERVER_CHOICE, choice);
    ApiService.setServerChoice(choice);
  }

  static Future<String> getServerChoice() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(KEY_SERVER_CHOICE) ?? 'cloudflare';
  }

  static Future<bool> getSemesterEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_SEMESTER_PROGRESS_ENABLED) ?? false;
  }

  static Future<DateTime?> getSemesterStart() async {
    final prefs = await StorageService.prefs;
    String? s = prefs.getString(KEY_SEMESTER_START);
    return s != null ? DateTime.tryParse(s) : null;
  }

  static Future<DateTime?> getSemesterEnd() async {
    final prefs = await StorageService.prefs;
    String? s = prefs.getString(KEY_SEMESTER_END);
    return s != null ? DateTime.tryParse(s) : null;
  }

  static Future<void> updateLastAutoSyncTime() async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(
        KEY_LAST_AUTO_SYNC, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastAutoSyncTime() async {
    final prefs = await StorageService.prefs;
    int? timestamp = prefs.getInt(KEY_LAST_AUTO_SYNC);
    if (timestamp != null)
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
          .toLocal();
    return null;
  }

  // Island bounds persistence helpers — uses file-based storage instead of
  // SharedPreferences because the island runs in a separate Flutter engine
  // and SharedPreferences is engine-isolated.
  static Future<File> _islandBoundsFile(String islandId) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/island_bounds_$islandId.json');
  }

  static Future<void> saveIslandBounds(
      String islandId, Map<String, dynamic> bounds) async {
    try {
      final file = await _islandBoundsFile(islandId);
      await file.writeAsString(jsonEncode(bounds));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getIslandBounds(String islandId) async {
    try {
      final file = await _islandBoundsFile(islandId);
      if (!await file.exists()) return null;
      final s = await file.readAsString();
      final m = jsonDecode(s);
      if (m is Map && m.isNotEmpty) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return null;
  }

  // ==========================================
  // 🔄 大模型重试配置
  // ==========================================

  /// 获取大模型重试次数，默认3次
  static Future<int> getLLMRetryCount() async {
    final prefs = await StorageService.prefs;
    return prefs.getInt(KEY_LLM_RETRY_COUNT) ?? 3;
  }

  /// 设置大模型重试次数
  static Future<void> setLLMRetryCount(int count) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(KEY_LLM_RETRY_COUNT, count);
  }

  // ==========================================
  // 📋 待确认待办数据（用于通知点击后的二次确认）
  // ==========================================

  /// 保存待确认的待办数据
  static Future<void> savePendingTodoConfirm({
    required String imagePath,
    required List<Map<String, dynamic>> results,
  }) async {
    final prefs = await StorageService.prefs;
    final data = jsonEncode({
      'imagePath': imagePath,
      'results': results,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(KEY_PENDING_TODO_CONFIRM, data);
  }

  /// 获取待确认的待办数据
  static Future<Map<String, dynamic>?> getPendingTodoConfirm() async {
    final prefs = await StorageService.prefs;
    final data = prefs.getString(KEY_PENDING_TODO_CONFIRM);
    if (data == null) return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 清除待确认的待办数据
  static Future<void> clearPendingTodoConfirm() async {
    final prefs = await StorageService.prefs;
    await prefs.remove(KEY_PENDING_TODO_CONFIRM);
  }

  // ==========================================
  // 🔔 通知管理设置
  // ==========================================

  static Future<bool> isLiveActivityNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_LIVE_ENABLED) ?? true;
  }

  static Future<void> setLiveActivityNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_LIVE_ENABLED, enabled);
  }

  static Future<bool> isNormalNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_NORMAL_ENABLED) ?? true;
  }

  static Future<void> setNormalNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_NORMAL_ENABLED, enabled);
  }

  static Future<bool> isCourseNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_COURSE_ENABLED) ?? true;
  }

  static Future<void> setCourseNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_COURSE_ENABLED, enabled);
  }

  static Future<bool> isQuizNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_QUIZ_ENABLED) ?? true;
  }

  static Future<void> setQuizNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_QUIZ_ENABLED, enabled);
  }

  static Future<bool> isTodoSummaryNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_TODO_SUMMARY_ENABLED) ?? true;
  }

  static Future<void> setTodoSummaryNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_TODO_SUMMARY_ENABLED, enabled);
  }

  static Future<bool> isSpecialTodoNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_SPECIAL_TODO_ENABLED) ?? true;
  }

  static Future<void> setSpecialTodoNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_SPECIAL_TODO_ENABLED, enabled);
  }

  static Future<bool> isPomodoroNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_POMODORO_ENABLED) ?? true;
  }

  static Future<void> setPomodoroNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_POMODORO_ENABLED, enabled);
  }

  static Future<bool> isTodoRecognizeNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_TODO_RECOGNIZE_ENABLED) ?? true;
  }

  static Future<void> setTodoRecognizeNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_TODO_RECOGNIZE_ENABLED, enabled);
  }

  static Future<bool> isTodoLiveNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_TODO_LIVE_ENABLED) ?? true;
  }

  static Future<void> setTodoLiveNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_TODO_LIVE_ENABLED, enabled);
  }

  static Future<bool> isPomodoroEndNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_POMODORO_END_ENABLED) ?? true;
  }

  static Future<void> setPomodoroEndNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_POMODORO_END_ENABLED, enabled);
  }

  static Future<bool> isReminderNotificationEnabled() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_NOTIFY_REMINDER_ENABLED) ?? true;
  }

  static Future<void> setReminderNotificationEnabled(bool enabled) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_NOTIFY_REMINDER_ENABLED, enabled);
  }

  static Future<int> getCourseReminderMinutes() async {
    final prefs = await StorageService.prefs;
    return prefs.getInt(KEY_COURSE_REMINDER_MINUTES) ?? 15;
  }

  static Future<void> setCourseReminderMinutes(int minutes) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(KEY_COURSE_REMINDER_MINUTES, minutes);
  }

  static Future<bool> isPrivacyPolicyAgreed() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_PRIVACY_AGREED) ?? false;
  }

  static Future<void> setPrivacyPolicyAgreed(bool agreed,
      {String? date}) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_PRIVACY_AGREED, agreed);
    if (agreed) {
      final versionDate = date ?? await _getPrivacyPolicyCurrentVersion();
      await prefs.setString(KEY_PRIVACY_DATE, versionDate);
    }
  }

  static Future<bool> isPrivacyPolicyUpToDate() async {
    final prefs = await StorageService.prefs;
    final storedDate = prefs.getString(KEY_PRIVACY_DATE);
    if (storedDate == null) return false;

    final cachedVersion = prefs.getString(KEY_PRIVACY_CACHED_VERSION);
    final cacheTime = prefs.getInt(KEY_PRIVACY_CACHE_TIME) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Check if we need to refresh the cache in the background
    if (cachedVersion == null ||
        now - cacheTime >= PRIVACY_CACHE_DURATION.inMilliseconds) {
      // Fire-and-forget background fetch so we don't block the UI app startup
      _getPrivacyPolicyCurrentVersion();
    }

    if (cachedVersion != null) {
      return _compareDates(storedDate, cachedVersion) >= 0;
    }

    // Default to true if no cache is available so we don't popup incorrectly on network failure
    return true;
  }

  /// 从 GitHub 获取隐私政策的版本日期，包含缓存机制
  static Future<String> _getPrivacyPolicyCurrentVersion() async {
    final prefs = await StorageService.prefs;

    // 检查缓存是否有效
    final cachedVersion = prefs.getString(KEY_PRIVACY_CACHED_VERSION);
    final cacheTime = prefs.getInt(KEY_PRIVACY_CACHE_TIME) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (cachedVersion != null &&
        now - cacheTime < PRIVACY_CACHE_DURATION.inMilliseconds) {
      debugPrint('[Privacy] Using cached version: $cachedVersion');
      return cachedVersion;
    }

    // 从网络获取
    try {
      debugPrint('[Privacy] Fetching version from GitHub...');
      final response = await http
          .get(Uri.parse(PRIVACY_RAW_URL))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final version = _extractPrivacyVersionDate(response.body);
        if (version.isNotEmpty) {
          // 缓存结果
          await prefs.setString(KEY_PRIVACY_CACHED_VERSION, version);
          await prefs.setInt(KEY_PRIVACY_CACHE_TIME, now);
          debugPrint('[Privacy] Updated version: $version');
          return version;
        }
      }
    } catch (e) {}

    // 如果网络请求失败但有缓存，返回缓存的版本
    if (cachedVersion != null) {
      return cachedVersion;
    }

    // 默认返回当前日期
    final defaultDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return defaultDate;
  }

  /// 从隐私政策 Markdown 内容中提取版本日期
  /// 格式例子: **版本日期：2026年4月11日** 或 **版本日期：2026-04-11**
  static String _extractPrivacyVersionDate(String content) {
    try {
      // 匹配 "版本日期：YYYY年M月D日" 格式
      final pattern1 = RegExp(r'版本日期[：:]?\s*(\d{4})年(\d{1,2})月(\d{1,2})日');
      final match1 = pattern1.firstMatch(content);
      if (match1 != null) {
        final year = match1.group(1)!;
        final month = match1.group(2)!.padLeft(2, '0');
        final day = match1.group(3)!.padLeft(2, '0');
        return '$year-$month-$day';
      }

      // 匹配 "版本日期：YYYY-MM-DD" 格式
      final pattern2 = RegExp(r'版本日期[：:]?\s*(\d{4}-\d{2}-\d{2})');
      final match2 = pattern2.firstMatch(content);
      if (match2 != null) {
        return match2.group(1)!;
      }

      debugPrint('[Privacy] Could not extract version date from content');
      return '';
    } catch (e) {
      debugPrint('[Privacy] Error extracting version date: $e');
      return '';
    }
  }

  static int _compareDates(String a, String b) {
    try {
      final dateA = DateTime.parse(a);
      final dateB = DateTime.parse(b);
      return dateA.compareTo(dateB);
    } catch (_) {
      return a.compareTo(b);
    }
  }

  static Future<void> withdrawPrivacyAgreement() async {
    final prefs = await StorageService.prefs;
    await prefs.remove(KEY_PRIVACY_AGREED);
    await prefs.remove(KEY_PRIVACY_DATE);
  }

  static void dispose() {
    _recurrenceCheckCache.clear();
    _lastRecurrenceCheckDate = null;
  }

  static Future<String> getWallpaperProvider() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(KEY_WALLPAPER_PROVIDER) ?? 'bing';
  }

  static Future<void> saveWallpaperProvider(String provider) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(KEY_WALLPAPER_PROVIDER, provider);
  }

  static Future<String> getWallpaperImageFormat() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(KEY_WALLPAPER_IMAGE_FORMAT) ?? 'jpg';
  }

  static Future<void> saveWallpaperImageFormat(String format) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(KEY_WALLPAPER_IMAGE_FORMAT, format);
  }

  static Future<int> getWallpaperIndex() async {
    final prefs = await StorageService.prefs;
    return prefs.getInt(KEY_WALLPAPER_INDEX) ?? 0;
  }

  static Future<void> saveWallpaperIndex(int index) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(KEY_WALLPAPER_INDEX, index);
  }

  static Future<String> getWallpaperMkt() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(KEY_WALLPAPER_MKT) ?? 'zh-CN';
  }

  static Future<void> saveWallpaperMkt(String mkt) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(KEY_WALLPAPER_MKT, mkt);
  }

  static Future<String> getWallpaperResolution() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(KEY_WALLPAPER_RESOLUTION) ?? '1920';
  }

  static Future<void> saveWallpaperResolution(String resolution) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(KEY_WALLPAPER_RESOLUTION, resolution);
  }

  static Future<bool> getTodoFoldersInline() async {
    final prefs = await StorageService.prefs;
    return prefs.getBool(KEY_TODO_FOLDERS_INLINE) ??
        true; // Defaults to embedded/inline
  }

  static Future<void> setTodoFoldersInline(bool inline) async {
    final prefs = await StorageService.prefs;
    await prefs.setBool(KEY_TODO_FOLDERS_INLINE, inline);
  }

  static Future<void> saveLastCourseImportUrl(String url) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(KEY_LAST_COURSE_IMPORT_URL, url);
  }

  static Future<String?> getLastCourseImportUrl() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(KEY_LAST_COURSE_IMPORT_URL);
  }

  // categoryGroupId -> minutes
  static Future<Map<String, int>> getCategoryReminderMinutes(
      String username) async {
    final prefs = await StorageService.prefs;
    final jsonStr =
        prefs.getString("${KEY_CATEGORY_REMINDER_MINUTES}_$username");
    if (jsonStr == null) return {};
    try {
      final Map<String, dynamic> rawResult = jsonDecode(jsonStr);
      return rawResult.map((key, value) => MapEntry(key, value as int));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveCategoryReminderMinutes(
      String username, Map<String, int> data) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(
        "${KEY_CATEGORY_REMINDER_MINUTES}_$username", jsonEncode(data));
  }
}
