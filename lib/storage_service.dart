import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'package:math_quiz_app/services/api_service.dart';

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
  // 新增：屏幕时间历史缓存，用于近七日图表
  // ignore: constant_identifier_names
  static const String KEY_SCREEN_TIME_HISTORY = "screen_time_history";

  // 新增：应用分类映射缓存
  // ignore: constant_identifier_names
  static const String KEY_APP_MAPPINGS = "app_category_mappings";
  // ignore: constant_identifier_names
  static const String KEY_LAST_MAPPINGS_SYNC = "last_mappings_sync";

  static bool _isSyncing = false;

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

  static Future<void> saveLoginSession(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_CURRENT_USER, username);
  }

  static Future<String?> getLoginSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(KEY_CURRENT_USER);
  }

  static Future<void> clearLoginSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(KEY_CURRENT_USER);
    await prefs.remove(KEY_LAST_SCREEN_TIME_SYNC);
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

  static Future<void> saveCountdowns(String username, List<CountdownItem> items, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> jsonList = items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_COUNTDOWNS}_$username", jsonList);
    if (sync) syncData(username);
  }

  static Future<List<CountdownItem>> getCountdowns(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList("${KEY_COUNTDOWNS}_$username") ?? [];
    return list.map((e) => CountdownItem.fromJson(jsonDecode(e))).toList();
  }

  static Future<void> saveTodos(String username, List<TodoItem> items, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> jsonList = items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("${KEY_TODOS}_$username", jsonList);
    if (sync) syncData(username);
  }

  static Future<List<TodoItem>> getTodos(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList("${KEY_TODOS}_$username") ?? [];
    List<TodoItem> todos = list.map((e) => TodoItem.fromJson(jsonDecode(e))).toList();
    DateTime now = DateTime.now();
    bool needSave = false;
    for (var todo in todos) {
      if (todo.recurrenceEndDate != null && now.isAfter(todo.recurrenceEndDate!)) continue;
      bool isNewDay = !_isSameDay(todo.lastUpdated, now);
      if (isNewDay) {
        if (todo.recurrence == RecurrenceType.daily) {
          todo.isDone = false;
          todo.lastUpdated = now;
          needSave = true;
        } else if (todo.recurrence == RecurrenceType.customDays && todo.customIntervalDays != null) {
          int diff = now.difference(todo.lastUpdated).inDays;
          if (diff >= todo.customIntervalDays!) {
            todo.isDone = false;
            todo.lastUpdated = now;
            needSave = true;
          }
        }
      }
    }
    if (needSave) await saveTodos(username, todos, sync: true);
    return todos;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // --- 屏幕时间缓存机制增强 ---
  static Future<void> saveScreenTimeCache(List<dynamic> stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_SCREEN_TIME_CACHE, jsonEncode(stats));

    // 核心新增：同步归档到按日期记录的历史中
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String? histStr = prefs.getString(KEY_SCREEN_TIME_HISTORY);
    Map<String, dynamic> history = {};
    if (histStr != null) {
      try { history = jsonDecode(histStr); } catch (_) {}
    }

    // 更新今日的历史记录快照
    history[today] = stats;

    // 清理老旧数据，最多保留 14 天
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

  // 获取屏幕时间历史缓存数据
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

  // --- 应用分类映射缓存机制 ---

  static Future<void> syncAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    int? lastSync = prefs.getInt(KEY_LAST_MAPPINGS_SYNC);
    DateTime now = DateTime.now();

    // 检查是否在 7 天内同步过
    if (lastSync != null) {
      DateTime lastDate = DateTime.fromMillisecondsSinceEpoch(lastSync);
      if (now.difference(lastDate).inDays < 7) {
        return; // 7天内无需重复拉取
      }
    }

    List<dynamic> mappings = await ApiService.fetchAppMappings();
    if (mappings.isNotEmpty) {
      Map<String, String> lookupMap = {};
      for (var item in mappings) {
        String pkg = item['package_name'] ?? '';
        String mapped = item['mapped_name'] ?? '';
        String cat = item['category'] ?? '未分类';

        // 双重保险：包名和中文名都作为键映射到分类，解决手机端系统转名导致的匹配失效
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

  // --- 核心同步 ---
  static Future<bool> syncData(String username) async {
    if (_isSyncing) return false;
    _isSyncing = true;
    bool hasChanges = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) return false;

      // 1. 同步分数 (略)
      // ...

      // 2. 同步待办事项 (LWW)
      List<TodoItem> localTodos = await getTodos(username);
      List<dynamic> cloudTodos = await ApiService.fetchTodos(userId);
      Map<String, dynamic> cloudTodoMap = { for (var t in cloudTodos) t['content']: t };

      List<TodoItem> todosToRemove = [];
      for (var local in localTodos) {
        if (cloudTodoMap.containsKey(local.title)) {
          var cloud = cloudTodoMap[local.title];
          DateTime cloudTime = _parseCloudTime(cloud['updated_at'] ?? cloud['created_at']);
          bool isCloudDeleted = (cloud['is_deleted'] == 1 || cloud['is_deleted'] == true);

          if (cloudTime.isAfter(local.lastUpdated)) {
            if (isCloudDeleted) {
              todosToRemove.add(local);
              hasChanges = true;
            } else {
              bool cloudDone = cloud['is_completed'] == 1 || cloud['is_completed'] == true;
              if (local.isDone != cloudDone) {
                local.isDone = cloudDone;
                local.lastUpdated = cloudTime;
                hasChanges = true;
              }
            }
          } else if (local.lastUpdated.isAfter(cloudTime)) {
            await ApiService.toggleTodo(cloud['id'], local.isDone);
          }
        } else {
          if (!local.isDone) await ApiService.addTodo(userId, local.title, timestamp: local.lastUpdated.millisecondsSinceEpoch);
        }
      }
      localTodos.removeWhere((t) => todosToRemove.contains(t));

      // 3. 同步倒计时 (修复删除逻辑)
      List<CountdownItem> localCountdowns = await getCountdowns(username);
      List<dynamic> cloudCountdowns = await ApiService.fetchCountdowns(userId);
      Map<String, dynamic> cloudCdMap = { for (var c in cloudCountdowns) c['title']: c };

      List<CountdownItem> cdsToRemove = [];

      for (var local in localCountdowns) {
        if (cloudCdMap.containsKey(local.title)) {
          var cloud = cloudCdMap[local.title];
          DateTime cloudTime = _parseCloudTime(cloud['updated_at']);
          bool isCloudDeleted = (cloud['is_deleted'] == 1 || cloud['is_deleted'] == true);

          if (cloudTime.isAfter(local.lastUpdated)) {
            if (isCloudDeleted) {
              cdsToRemove.add(local);
              hasChanges = true;
            } else {
              local.targetDate = DateTime.tryParse(cloud['target_time']) ?? local.targetDate;
              local.lastUpdated = cloudTime;
              hasChanges = true;
            }
          } else if (local.lastUpdated.isAfter(cloudTime)) {
            await ApiService.addCountdown(userId, local.title, local.targetDate, local.lastUpdated.millisecondsSinceEpoch);
          }
        } else {
          await ApiService.addCountdown(userId, local.title, local.targetDate, local.lastUpdated.millisecondsSinceEpoch);
        }
      }
      localCountdowns.removeWhere((item) => cdsToRemove.contains(item));

      for (var cloud in cloudCountdowns) {
        bool isCloudDeleted = (cloud['is_deleted'] == 1 || cloud['is_deleted'] == true);
        if (!isCloudDeleted && !localCountdowns.any((l) => l.title == cloud['title'])) {
          localCountdowns.add(CountdownItem(
            title: cloud['title'],
            targetDate: DateTime.parse(cloud['target_time']),
            lastUpdated: _parseCloudTime(cloud['updated_at']),
          ));
          hasChanges = true;
        }
      }

      if (hasChanges){
        await saveTodos(username, localTodos, sync: false);
        await saveCountdowns(username, localCountdowns, sync: false);
      }
    } catch (e) { print("同步异常: $e"); } finally { _isSyncing = false; }
    return hasChanges;
  }

  static DateTime _parseCloudTime(dynamic timeData) {
    if (timeData == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (timeData is int) return DateTime.fromMillisecondsSinceEpoch(timeData);
    if (timeData is String) {
      String t = timeData;
      if (!t.endsWith('Z') && !t.contains('+')) t += 'Z';
      return DateTime.tryParse(t)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}