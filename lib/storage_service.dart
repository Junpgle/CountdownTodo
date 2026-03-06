import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'services/api_service.dart';

class StorageService {
  // ignore: constant_identifier_names
  static const String KEY_USERS = "users_data";
  // ignore: constant_identifier_names
  static const String KEY_LEADERBOARD = "leaderboard_data";
  // ignore: constant_identifier_names
  static const String KEY_SETTINGS = "quiz_settings";
  // ignore: constant_identifier_names
  static const String KEY_CURRENT_USER = "current_login_user";

  // ignore: constant_identifier_names
  static const String KEY_TODOS = "user_todos";
  // ignore: constant_identifier_names
  static const String KEY_COUNTDOWNS = "user_countdowns";

  // ignore: constant_identifier_names
  static const String KEY_SCREEN_TIME_CACHE = "screen_time_cache";
  // ignore: constant_identifier_names
  static const String KEY_LAST_SCREEN_TIME_SYNC = "last_screen_time_sync";
  // ignore: constant_identifier_names
  static const String KEY_SCREEN_TIME_HISTORY = "screen_time_history";

  // ignore: constant_identifier_names
  static const String KEY_APP_MAPPINGS = "app_category_mappings";
  // ignore: constant_identifier_names
  static const String KEY_LAST_MAPPINGS_SYNC = "last_mappings_sync";

  // 🛡️ 鉴权验证相关缓存
  static const String KEY_AUTH_TOKEN = "auth_session_token";
  static const String KEY_DEVICE_ID = "app_device_uuid";

  // 设置相关的 Key
  static const String KEY_SYNC_INTERVAL = "app_sync_interval"; // 同步频率 (分钟)
  static const String KEY_THEME_MODE = "app_theme_mode"; // 主题外观
  static const String KEY_LAST_AUTO_SYNC = "last_auto_sync_time"; // 上次自动同步的时间

  // 学期进度设置相关的 Key
  static const String KEY_SEMESTER_PROGRESS_ENABLED = "semester_progress_enabled";
  static const String KEY_SEMESTER_START = "semester_start_date";
  static const String KEY_SEMESTER_END = "semester_end_date";

  static bool _isSyncing = false;

  // 全局监听主题变化的状态
  static ValueNotifier<String> themeNotifier = ValueNotifier('system');

  // ==========================================
  // 🛡️ 设备唯一标识管理
  // ==========================================
  static Future<String> _getUniqueDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(KEY_DEVICE_ID);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(KEY_DEVICE_ID, deviceId);
    }
    return deviceId;
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
      ApiService.setToken(token); // 立刻向请求引擎注入 Token
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
    ApiService.setToken(''); // 清空内存 Token
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
      'min_num1': 0, 'max_num1': 50,
      'min_num2': 0, 'max_num2': 50,
      'max_result': 100,
    };
  }

  // ==========================================
  // 测验历史与排行榜
  // ==========================================
  static Future<void> saveHistory(String username, int score, int duration, String details) async {
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
          String timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(map['date']));
          return "时间: $timeStr\n得分: ${map['score']}\n用时: ${map['duration']}秒\n详情:\n${map['details']}\n-----------------";
        }
        return item;
      } catch (e) { return item; }
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
          if (date.year == now.year && date.month == now.month && date.day == now.day) todayCount++;
        }
        totalQuestions += 10;
        totalCorrect += (score ~/ 10);
        if (score == 100) { hasPerfectScore = true; if (duration < bestTime) bestTime = duration; }
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
    double accuracy = totalQuestions == 0 ? 0.0 : (totalCorrect / totalQuestions);
    return { 'accuracy': accuracy, 'bestTime': hasPerfectScore ? bestTime : null, 'todayCount': todayCount };
  }

  static Future<void> updateLeaderboard(String username, int score, int duration) async {
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
  // 本地数据读写 (自带安全验证与逻辑保留)
  // ==========================================
  static Future<void> saveCountdowns(String username, List<CountdownItem> items, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> jsonList = items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_COUNTDOWNS}_$username", jsonList);
    if (sync) Future.microtask(() => syncData(username));
  }

  static Future<List<CountdownItem>> getCountdowns(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList("${KEY_COUNTDOWNS}_$username") ?? [];
    List<CountdownItem> result = [];
    for (var e in list) {
      try {
        result.add(CountdownItem.fromJson(jsonDecode(e)));
      } catch (_) {}
    }
    return result;
  }

  static Future<void> saveTodos(String username, List<TodoItem> items, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> jsonList = items.map((e) => jsonEncode(e.toJson())).toList();
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
      } catch (err) { print("Parse Todo Error: $err"); }
    }

    // 🚀 保留原有的日常重置逻辑 (利用 markAsChanged() 升级版本并触发同步)
    DateTime now = DateTime.now();
    bool needSave = false;
    for (var todo in todos) {
      if (todo.recurrenceEndDate != null && now.isAfter(todo.recurrenceEndDate!)) continue;

      DateTime lastUpdateDate = DateTime.fromMillisecondsSinceEpoch(todo.updatedAt);
      bool isNewDay = !_isSameDay(lastUpdateDate, now);

      if (isNewDay) {
        if (todo.recurrence == RecurrenceType.daily) {
          todo.isDone = false;
          todo.markAsChanged();
          needSave = true;
        } else if (todo.recurrence == RecurrenceType.customDays && todo.customIntervalDays != null) {
          int diff = now.difference(lastUpdateDate).inDays;
          if (diff >= todo.customIntervalDays!) {
            todo.isDone = false;
            todo.markAsChanged();
            needSave = true;
          }
        }
      }
    }
    if (needSave) await saveTodos(username, todos, sync: true);

    // 注意：UI 展示时应过滤掉 isDeleted == true 的项目，这里全部返回以用于同步
    return todos;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ==========================================
  // 🚀 彻底的逻辑删除机制 (不再直接移除元素，而是标记)
  // ==========================================
  static Future<void> deleteTodoGlobally(String username, String idToDelete) async {
    List<TodoItem> localTodos = await getTodos(username);
    int index = localTodos.indexWhere((t) => t.id == idToDelete);
    if (index != -1) {
      localTodos[index].isDeleted = true;
      localTodos[index].markAsChanged(); // 触发 Version 升级
      await saveTodos(username, localTodos, sync: true); // 触发增量同步
    }
  }

  static Future<void> deleteCountdownGlobally(String username, String idToDelete) async {
    List<CountdownItem> localCds = await getCountdowns(username);
    int index = localCds.indexWhere((t) => t.id == idToDelete);
    if (index != -1) {
      localCds[index].isDeleted = true;
      localCds[index].markAsChanged();
      await saveCountdowns(username, localCds, sync: true);
    }
  }

  // ==========================================
  // 屏幕时间缓存机制增强
  // ==========================================
  static Future<void> saveScreenTimeCache(List<dynamic> stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_SCREEN_TIME_CACHE, jsonEncode(stats));

    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String? histStr = prefs.getString(KEY_SCREEN_TIME_HISTORY);
    Map<String, dynamic> history = {};
    if (histStr != null) {
      try { history = jsonDecode(histStr); } catch (_) {}
    }

    history[today] = stats;

    if (history.length > 14) {
      var keys = history.keys.toList()..sort();
      while (history.length > 14) {
        history.remove(keys.removeAt(0));
      }
    }
    await prefs.setString(KEY_SCREEN_TIME_HISTORY, jsonEncode(history));
  }

  static Future<List<dynamic>> getScreenTimeCache() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(KEY_SCREEN_TIME_CACHE);
    if (jsonStr != null) { try { return jsonDecode(jsonStr); } catch (_) { return []; } }
    return [];
  }

  static Future<Map<String, List<dynamic>>> getScreenTimeHistory() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(KEY_SCREEN_TIME_HISTORY);
    if (jsonStr != null) {
      try {
        Map<String, dynamic> raw = jsonDecode(jsonStr);
        return raw.map((key, value) => MapEntry(key, List<dynamic>.from(value)));
      } catch (_) {}
    }
    return {};
  }

  static Future<void> updateLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(KEY_LAST_SCREEN_TIME_SYNC, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    int? timestamp = prefs.getInt(KEY_LAST_SCREEN_TIME_SYNC);
    if (timestamp != null) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return null;
  }

  // ==========================================
  // 应用分类映射缓存机制
  // ==========================================
  static Future<void> syncAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    int? lastSync = prefs.getInt(KEY_LAST_MAPPINGS_SYNC);
    DateTime now = DateTime.now();

    if (lastSync != null) {
      DateTime lastDate = DateTime.fromMillisecondsSinceEpoch(lastSync);
      if (now.difference(lastDate).inDays < 7) {
        return;
      }
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
  // 🚀 核心：增量同步算法 (Delta Sync)
  // ==========================================
  static Future<bool> syncData(
      String username, {
        bool syncTodos = true,
        bool syncCountdowns = true,
        BuildContext? context,
      }) async {

    if (!syncTodos && !syncCountdowns) return false;
    if (_isSyncing) return false;
    _isSyncing = true;
    bool hasChanges = false;
    bool dialogClosed = false;

    ValueNotifier<String> statusNotifier = ValueNotifier("准备增量同步...");

    if (context != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(width: 20),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: statusNotifier,
                    builder: (context, val, child) => Text(val, style: const TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("User not logged in");

      final String deviceId = await _getUniqueDeviceId();
      final int lastSyncTime = prefs.getInt('last_sync_time_$username') ?? 0;

      // 1. 过滤出本地发生变化的数据 (脏数据)
      statusNotifier.value = "打包增量数据...";

      List<TodoItem> allLocalTodos = [];
      List<Map<String, dynamic>> dirtyTodos = [];
      if (syncTodos) {
        allLocalTodos = await getTodos(username);
        dirtyTodos = allLocalTodos
            .where((t) => t.updatedAt > lastSyncTime)
            .map((t) => t.toJson())
            .toList();
      }

      List<CountdownItem> allLocalCountdowns = [];
      List<Map<String, dynamic>> dirtyCountdowns = [];
      if (syncCountdowns) {
        allLocalCountdowns = await getCountdowns(username);
        dirtyCountdowns = allLocalCountdowns
            .where((c) => c.updatedAt > lastSyncTime)
            .map((c) => c.toJson())
            .toList();
      }

      statusNotifier.value = "与服务器对比变化...";

      // 2. 发送增量请求
      final response = await ApiService.postDeltaSync(
        userId: userId,
        lastSyncTime: lastSyncTime,
        deviceId: deviceId,
        todosChanges: dirtyTodos,
        countdownsChanges: dirtyCountdowns,
      );

      if (response['success'] != true) {
        if (response['isLimitExceeded'] == true) throw Exception("LIMIT_EXCEEDED:${response['message']}");
        throw Exception("${response['message'] ?? '发生未知错误'}");
      }

      statusNotifier.value = "合并远端数据...";

      // ==========================================
      // 3. 智能合并服务器拉取下来的变化 (LWW on Version)
      // ==========================================
      List<dynamic> serverTodos = response['server_todos'];
      List<dynamic> serverCountdowns = response['server_countdowns'];
      int newSyncTime = response['new_sync_time'];

      if (serverTodos.isNotEmpty && syncTodos) {
        for (var raw in serverTodos) {
          TodoItem serverItem = TodoItem.fromJson(raw);
          int index = allLocalTodos.indexWhere((l) => l.id == serverItem.id);

          if (index == -1) {
            // 本地没有这条数据，且服务器没有删除它，则插入
            if (!serverItem.isDeleted) allLocalTodos.add(serverItem);
            hasChanges = true;
          } else {
            // 本地存在，比较版本号：服务器版本大于等于本地版本才覆盖
            if (serverItem.version > allLocalTodos[index].version) {
              allLocalTodos[index] = serverItem;
              hasChanges = true;
            }
          }
        }
      }

      if (serverCountdowns.isNotEmpty && syncCountdowns) {
        for (var raw in serverCountdowns) {
          CountdownItem serverItem = CountdownItem.fromJson(raw);
          int index = allLocalCountdowns.indexWhere((l) => l.id == serverItem.id);

          if (index == -1) {
            if (!serverItem.isDeleted) allLocalCountdowns.add(serverItem);
            hasChanges = true;
          } else {
            if (serverItem.version > allLocalCountdowns[index].version) {
              allLocalCountdowns[index] = serverItem;
              hasChanges = true;
            }
          }
        }
      }

      // 4. 持久化数据与最新同步时间
      statusNotifier.value = "保存同步结果...";

      // 注意此处强制静默保存，防止再次触发死循环同步
      if (syncTodos && hasChanges) await saveTodos(username, allLocalTodos, sync: false);
      if (syncCountdowns && hasChanges) await saveCountdowns(username, allLocalCountdowns, sync: false);

      await prefs.setInt('last_sync_time_$username', newSyncTime);

      statusNotifier.value = "同步完成！";
      if (context != null) await Future.delayed(const Duration(milliseconds: 400));

    } catch (e) {
      print("增量同步异常中断: $e");
      if (context != null && context.mounted && !dialogClosed) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogClosed = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("同步异常: $e")));
      }
      rethrow;
    } finally {
      _isSyncing = false;
      if (context != null && context.mounted && !dialogClosed) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogClosed = true;
      }
    }

    return hasChanges;
  }

  // ==========================================
  // 通用配置系统 (基础环境、同步配置、学期进度)
  // ==========================================
  static Future<void> saveAppSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) await prefs.setInt(key, value);
    if (value is String) await prefs.setString(key, value);
    if (value is bool) await prefs.setBool(key, value);
  }

  static Future<int> getSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(KEY_SYNC_INTERVAL) ?? 0;
  }

  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(KEY_THEME_MODE) ?? 'system';
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
    await prefs.setInt(KEY_LAST_AUTO_SYNC, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastAutoSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    int? timestamp = prefs.getInt(KEY_LAST_AUTO_SYNC);
    if (timestamp != null) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return null;
  }
}