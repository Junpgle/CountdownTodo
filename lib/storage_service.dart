import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'services/api_service.dart';

class StorageService {
  // --- 常量定义 ---
  static const String KEY_USERS = "users_data";
  static const String KEY_LEADERBOARD = "leaderboard_data";
  static const String KEY_SETTINGS = "quiz_settings";
  static const String KEY_CURRENT_USER = "current_login_user";
  static const String KEY_TODOS = "user_todos";
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

  static bool _isSyncing = false;
  static ValueNotifier<String> themeNotifier = ValueNotifier('system');

  // ==========================================
  // 🛡️ 设备信息与标识管理 (解决未知设备问题)
  // ==========================================

  /// 获取设备唯一 UUID (用于后端同步过滤)
  static Future<String> _getUniqueDeviceId(String username) async {
    final prefs = await SharedPreferences.getInstance();
    String accountDeviceKey = "${KEY_DEVICE_ID}_$username";
    String? deviceId = prefs.getString(accountDeviceKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(accountDeviceKey, deviceId);
    }
    return deviceId;
  }

  /// 核心：获取“人话”版的设备型号与类型 (手机/平板/PC)
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
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(KEY_CURRENT_USER) ?? 'default';
    return _getUniqueDeviceId(username);
  }

  // ==========================================
  // 基础配置与用户系统
  // ==========================================
  static Future<void> initTheme() async {
    final prefs = await SharedPreferences.getInstance();
    themeNotifier.value = prefs.getString(KEY_THEME_MODE) ?? 'system';
  }

  static Future<bool> register(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> users = {};
    String? usersJson = prefs.getString(KEY_USERS);
    if (usersJson != null) users = jsonDecode(usersJson);
    if (users.containsKey(username)) return false;
    users[username] = password;
    await prefs.setString(KEY_USERS, jsonEncode(users));
    return true;
  }

  static Future<bool> login(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString(KEY_AUTH_TOKEN);
    if (token != null && token.isNotEmpty) {
      ApiService.setToken(token);
    }
    return prefs.getString(KEY_CURRENT_USER);
  }

  static Future<void> clearLoginSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(KEY_CURRENT_USER);
    await prefs.remove(KEY_LAST_SCREEN_TIME_SYNC);
    await prefs.remove(KEY_AUTH_TOKEN);
    ApiService.setToken('');
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_SETTINGS, jsonEncode(settings));
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
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

  static Future<void> savePomodoroTags(
      String username, List<Map<String, dynamic>> tags) async {
    final prefs = await SharedPreferences.getInstance();
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
      {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, CountdownItem> dedupeMap = {};
    for (var item in items) {
      String id = item.id.toString();
      if (!dedupeMap.containsKey(id) ||
          item.updatedAt > dedupeMap[id]!.updatedAt) {
        dedupeMap[id] = item;
      }
    }
    List<String> jsonList =
        dedupeMap.values.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_COUNTDOWNS}_$username", jsonList);
    if (sync) Future.microtask(() => syncData(username));
  }

  static Future<List<CountdownItem>> getCountdowns(String username) async {
    final prefs = await SharedPreferences.getInstance();
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
      {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, TodoItem> dedupeMap = {};

    for (var item in items) {
      final existing = dedupeMap[item.id];
      if (existing == null || item.updatedAt > existing.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    List<TodoItem> result = dedupeMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    List<String> jsonList =
        dedupeMap.values.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_TODOS}_$username", jsonList);
    if (sync) Future.microtask(() => syncData(username));
  }

  static Future<List<TodoItem>> getTodos(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList("${KEY_TODOS}_$username") ?? [];
    List<TodoItem> todos = [];

    for (var e in list) {
      try {
        todos.add(TodoItem.fromJson(jsonDecode(e)));
      } catch (err) {
        debugPrint("Parse Todo Error: $err");
      }
    }

    // 🚀 自动重置重复任务逻辑
    DateTime now = DateTime.now();
    bool needSave = false;

    for (var todo in todos) {
      if (todo.isDeleted) continue;
      if (todo.recurrence == RecurrenceType.none) continue;
      if (todo.recurrenceEndDate != null &&
          now.isAfter(todo.recurrenceEndDate!)) continue;

      final DateTime baseLocal = _getRecurrenceBaseDate(todo);
      final DateTime baseDay =
          DateTime(baseLocal.year, baseLocal.month, baseLocal.day);
      final DateTime today = DateTime(now.year, now.month, now.day);

      if (todo.recurrence == RecurrenceType.daily) {
        if (today.isAfter(baseDay)) {
          todo.isDone = false;
          _rollRecurrenceDateToToday(todo, now);
          todo.markAsChanged();
          needSave = true;
        }
      } else if (todo.recurrence == RecurrenceType.customDays &&
          todo.customIntervalDays != null &&
          todo.customIntervalDays! > 0) {
        int diffDays = today.difference(baseDay).inDays;
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
      await saveTodos(username, todos, sync: true);
    }

    return todos;
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
  // 时间日志 (Time Logs)
  // ==========================================
  static Future<void> saveTimeLogs(String username, List<TimeLogItem> items,
      {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
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
  static Future<void> saveScreenTimeCache(List<dynamic> stats) async {
    if (stats.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
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

    debugPrint("屏幕时间本地缓存已更新: $today, 记录条数: ${stats.length}");
  }

  static Future<List<dynamic>> getScreenTimeCache() async {
    final prefs = await SharedPreferences.getInstance();

    // 检查缓存是否是今天的
    int? lastSyncMs = prefs.getInt(KEY_LAST_SCREEN_TIME_SYNC);
    if (lastSyncMs != null) {
      DateTime lastSyncDate = DateTime.fromMillisecondsSinceEpoch(lastSyncMs).toLocal();
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
    final prefs = await SharedPreferences.getInstance();
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
    await prefs.remove('last_sync_time_$username');
  }

  static Future<bool> syncData(
      String username, {
        bool syncTodos = true,
        bool syncCountdowns = true,
        bool forceFullSync = false,
        BuildContext? context,
        bool syncTimeLogs = true,
      }) async {
    // 1. 状态锁：防止重复进入
    if (!syncTodos && !syncCountdowns && !syncTimeLogs) return false;
    if (_isSyncing) return false;
    _isSyncing = true;
    bool hasChanges = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("用户未登录");

      // 2. 环境信息准备
      final String deviceId = await _getUniqueDeviceId(username);
      final String friendlyName = await _getDetailedDeviceName();
      final int lastSyncTime = forceFullSync ? 0 : (prefs.getInt('last_sync_time_$username') ?? 0);

      // 3. 准备增量数据包 (Todos, Countdowns, TimeLogs)
      List<TodoItem> allLocalTodos = await getTodos(username);
      List<CountdownItem> allLocalCountdowns = await getCountdowns(username);
      List<TimeLogItem> allLocalTimeLogs = await getTimeLogs(username);

      List<Map<String, dynamic>> dirtyTodos = allLocalTodos
          .where((t) => t.updatedAt > lastSyncTime)
          .map((t) => t.toJson())
          .toList();
      List<Map<String, dynamic>> dirtyCountdowns = allLocalCountdowns
          .where((c) => c.updatedAt > lastSyncTime)
          .map((c) => c.toJson())
          .toList();
      List<Map<String, dynamic>> dirtyTimeLogs = allLocalTimeLogs
          .where((t) => t.updatedAt > lastSyncTime)
          .map((t) => t.toJson())
          .toList();

      // 4. 🚀 屏幕时间逻辑优化：处理日期污染问题
      Map<String, dynamic>? screenPayload;
      DateTime now = DateTime.now();
      String todayDate = DateFormat('yyyy-MM-dd').format(now);

      // 获取屏幕时间最后更新的物理时间
      int? lastScreenUpdateMs = prefs.getInt(KEY_LAST_SCREEN_TIME_SYNC);
      if (lastScreenUpdateMs != null) {
        DateTime lastUpdateDate = DateTime.fromMillisecondsSinceEpoch(lastScreenUpdateMs).toLocal();

        // 核心校验：只有缓存的最后更新时间是【今天】，才允许同步
        if (lastUpdateDate.year == now.year &&
            lastUpdateDate.month == now.month &&
            lastUpdateDate.day == now.day) {

          List<dynamic> localScreenStats = await getScreenTimeCache();
          if (localScreenStats.isNotEmpty) {
            screenPayload = {
              'device_name': friendlyName,
              'record_date': todayDate,
              'apps': localScreenStats
                  .map((e) => {'app_name': e['app_name'], 'duration': e['duration']})
                  .toList(),
            };
            debugPrint("准备同步今日屏幕时间: $todayDate (${localScreenStats.length} 条数据)");
          }
        } else {
          debugPrint("本地屏幕时间缓存已过期 (日期为 ${DateFormat('yyyy-MM-dd').format(lastUpdateDate)})，本次跳过推送。");
        }
      }

      // 5. 发起网络同步请求
      final response = await ApiService.postDeltaSync(
        userId: userId,
        lastSyncTime: lastSyncTime,
        deviceId: deviceId,
        todosChanges: dirtyTodos,
        countdownsChanges: dirtyCountdowns,
        timeLogsChanges: dirtyTimeLogs,
        screenTime: screenPayload,
      );

      if (response['success'] != true) {
        throw Exception("${response['message'] ?? '同步失败'}");
      }

      // 6. 🛡️ 数据合并逻辑 (LWW - Last Write Wins)

      // 合并 Todos
      List<dynamic> serverTodos = response['server_todos'] ?? [];
      for (var raw in serverTodos) {
        TodoItem sItem = TodoItem.fromJson(raw);
        int index = allLocalTodos.indexWhere((l) => l.id == sItem.id);
        if (index == -1) {
          if (!sItem.isDeleted) { allLocalTodos.add(sItem); hasChanges = true; }
        } else if (sItem.isDeleted || sItem.version > allLocalTodos[index].version || sItem.updatedAt > allLocalTodos[index].updatedAt) {
          allLocalTodos[index] = sItem;
          hasChanges = true;
        }
      }

      // 合并 Countdowns
      List<dynamic> serverCountdowns = response['server_countdowns'] ?? [];
      for (var raw in serverCountdowns) {
        CountdownItem sItem = CountdownItem.fromJson(raw);
        int index = allLocalCountdowns.indexWhere((l) => l.id == sItem.id);
        if (index == -1) {
          if (!sItem.isDeleted) { allLocalCountdowns.add(sItem); hasChanges = true; }
        } else if (sItem.isDeleted || sItem.version > allLocalCountdowns[index].version || sItem.updatedAt > allLocalCountdowns[index].updatedAt) {
          allLocalCountdowns[index] = sItem;
          hasChanges = true;
        }
      }

      // 合并 TimeLogs
      List<dynamic> serverTimeLogs = response['server_time_logs'] ?? [];
      for (var raw in serverTimeLogs) {
        TimeLogItem sItem = TimeLogItem.fromJson(raw);
        int index = allLocalTimeLogs.indexWhere((l) => l.id == sItem.id);
        if (index == -1) {
          if (!sItem.isDeleted) { allLocalTimeLogs.add(sItem); hasChanges = true; }
        } else if (sItem.isDeleted || sItem.version > allLocalTimeLogs[index].version || sItem.updatedAt > allLocalTimeLogs[index].updatedAt) {
          allLocalTimeLogs[index] = sItem;
          hasChanges = true;
        }
      }

      // 7. 持久化数据
      if (hasChanges) {
        await saveTodos(username, allLocalTodos, sync: false);
        await saveCountdowns(username, allLocalCountdowns, sync: false);
        await saveTimeLogs(username, allLocalTimeLogs, sync: false);
      }

      // 8. 更新同步水位线
      int newSyncTime = response['new_sync_time'] ?? DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('last_sync_time_$username', newSyncTime);

      // 如果屏幕时间同步成功，可以在这里刷新 UI 用的 Cache 数据（如果后端有返回最新的聚合数据）
      if (response['screen_time_results'] != null) {
        await saveScreenTimeCache(response['screen_time_results']);
      }

    } catch (e) {
      debugPrint("同步异常: $e");
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("同步失败: $e")));
      }
      rethrow;
    } finally {
      _isSyncing = false;
    }
    return hasChanges;
  }

  // ==========================================
  // 偏好设置与状态管理
  // ==========================================
  static Future<void> saveAppSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) await prefs.setInt(key, value);
    if (value is String) await prefs.setString(key, value);
    if (value is bool) await prefs.setBool(key, value);
    if (key == KEY_THEME_MODE) themeNotifier.value = value;
  }

  static Future<int> getSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(KEY_SYNC_INTERVAL) ?? 0;
  }

  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(KEY_THEME_MODE) ?? 'system';
  }

  static Future<void> saveServerChoice(String choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_SERVER_CHOICE, choice);
    ApiService.setServerChoice(choice);
  }

  static Future<String> getServerChoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(KEY_SERVER_CHOICE) ?? 'cloudflare';
  }

  static Future<bool> getSemesterEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(KEY_SEMESTER_PROGRESS_ENABLED) ?? false;
  }

  static Future<DateTime?> getSemesterStart() async {
    final prefs = await SharedPreferences.getInstance();
    String? s = prefs.getString(KEY_SEMESTER_START);
    return s != null ? DateTime.tryParse(s) : null;
  }

  static Future<DateTime?> getSemesterEnd() async {
    final prefs = await SharedPreferences.getInstance();
    String? s = prefs.getString(KEY_SEMESTER_END);
    return s != null ? DateTime.tryParse(s) : null;
  }

  static Future<void> updateLastAutoSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        KEY_LAST_AUTO_SYNC, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastAutoSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    int? timestamp = prefs.getInt(KEY_LAST_AUTO_SYNC);
    if (timestamp != null)
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
          .toLocal();
    return null;
  }
}
