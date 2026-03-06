import 'dart:convert';
import 'package:flutter/material.dart'; // 🚀 引入 material.dart 替代 foundation.dart，以使用 BuildContext 和高级弹窗
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
  // 🛡️ 新增：缓存用户的安全认证 Token
  static const String KEY_AUTH_TOKEN = "auth_session_token";

  // 设置相关的 Key
  static const String KEY_SYNC_INTERVAL = "app_sync_interval"; // 同步频率 (分钟)
  static const String KEY_THEME_MODE = "app_theme_mode"; // 主题外观
  static const String KEY_LAST_AUTO_SYNC = "last_auto_sync_time"; // 上次自动同步的时间

  // 新增：学期进度设置相关的 Key
  static const String KEY_SEMESTER_PROGRESS_ENABLED = "semester_progress_enabled";
  static const String KEY_SEMESTER_START = "semester_start_date";
  static const String KEY_SEMESTER_END = "semester_end_date";

  static bool _isSyncing = false;

  // 全局监听主题变化的状态
  static ValueNotifier<String> themeNotifier = ValueNotifier('system');

  // 在 App 启动时读取本地主题设置
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

  // 🚀 记录 Session 时一并存储并启用 Token
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
    // 恢复状态时，重载 Token 供通信使用
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

    // 安全的反序列化
    for (var e in list) {
      try {
        todos.add(TodoItem.fromJson(jsonDecode(e)));
      } catch (_) {}
    }

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

  // 🚀 倒计时依然保持通过 title 唯一性判断
  static Future<void> deleteCountdownGlobally(String username, String title) async {
    List<CountdownItem> localCds = await getCountdowns(username);
    localCds.removeWhere((c) => c.title == title);
    await saveCountdowns(username, localCds, sync: false);

    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId != null) {
      try {
        await ApiService.deleteCountdown(title);
      } catch (e) {
        print("全局删除倒计时失败: $e");
      }
    }
  }

  // 🚀 核心优化：直接基于 created_at 发送删除指令，不再依赖 DB_ID
  static Future<void> deleteTodoGlobally(String username, String idToDelete) async {
    List<TodoItem> localTodos = await getTodos(username);

    // 先找出这条待办，提取它的 createdAt 作为向云端汇报的唯一凭据
    TodoItem? targetTodo;
    try {
      targetTodo = localTodos.firstWhere((t) => t.id == idToDelete);
    } catch (_) {}

    localTodos.removeWhere((t) => t.id == idToDelete);
    await saveTodos(username, localTodos, sync: false);

    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId != null && targetTodo != null) {
      try {
        await ApiService.deleteTodo(targetTodo.createdAt.toIso8601String());
      } catch (e) {
        print("全局删除待办失败: $e");
      }
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // --- 屏幕时间缓存机制增强 ---
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

  // --- 应用分类映射缓存机制 ---
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
  // 🚀 核心同步机制优化 (引入 BuildContext 高级弹窗)
  // ==========================================
  static Future<bool> syncData(
      String username, {
        bool syncTodos = true,
        bool syncCountdowns = true,
        BuildContext? context, // 🚀 传入 context 即开启弹窗模式
      }) async {
    if (!syncTodos && !syncCountdowns) return false;

    if (_isSyncing) return false;
    _isSyncing = true;
    bool hasChanges = false;
    bool dialogClosed = false;

    // 🚀 创建局部状态通知器，控制弹窗内的实时文字刷新
    ValueNotifier<String> statusNotifier = ValueNotifier("准备同步...");

    // 只有在外界主动触发并传了 Context 的时候，才弹出居中的漂亮指示器
    if (context != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // 阻止点击外部关闭，强制等待同步完成
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5)
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: statusNotifier,
                    builder: (context, val, child) {
                      return Text(val, style: const TextStyle(fontSize: 15));
                    },
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
      if (userId == null) return false;

      statusNotifier.value = "正在打包本地数据...";

      // 1. 组装本地待办 Payload (不再发送无意义的 UUID，重点是 created_date)
      List<TodoItem> localTodos = [];
      List<Map<String, dynamic>> todoPayload = [];
      if (syncTodos) {
        localTodos = await getTodos(username);
        todoPayload = localTodos.map((t) => {
          'content': t.title,
          'is_completed': t.isDone,
          'is_deleted': false,
          'client_updated_at': t.lastUpdated.toIso8601String(),
          'due_date': t.dueDate?.toIso8601String(),
          'created_date': t.createdAt.toIso8601String(),
        }).toList();
      }

      // 2. 组装本地倒计时 Payload
      List<CountdownItem> localCountdowns = [];
      List<Map<String, dynamic>> countdownPayload = [];
      if (syncCountdowns) {
        localCountdowns = await getCountdowns(username);
        countdownPayload = localCountdowns.map((c) => {
          'title': c.title,
          'target_time': c.targetDate.toIso8601String(),
          'client_updated_at': c.lastUpdated.toIso8601String(),
          'is_deleted': false,
        }).toList();
      }

      statusNotifier.value = "正在与云端服务器通信...";

      // 3. 呼叫聚合同步 API 🚀
      final response = await ApiService.syncAll(
        userId: userId,
        todos: todoPayload,
        countdowns: countdownPayload,
      );

      if (response['success'] != true) {
        if (response['isLimitExceeded'] == true) {
          throw Exception("LIMIT_EXCEEDED:${response['message']}");
        }
        throw Exception("${response['message'] ?? '发生未知错误'}");
      }

      statusNotifier.value = "正在处理云端最新数据...";

      final data = response['data'] ?? {};

      String? tier = response['tier'] ?? data['tier'];
      int? syncCount = response['sync_count'] ?? data['sync_count'];
      int? syncLimit = response['sync_limit'] ?? data['sync_limit'];

      if (tier != null) {
        final Map<String, dynamic> statusCache = {
          'tier': tier,
          'sync_count': syncCount ?? 0,
          'sync_limit': syncLimit ?? 50,
        };
        await prefs.setString('account_status_cache_$userId', jsonEncode(statusCache));
        await prefs.setInt('account_status_time_$userId', DateTime.now().millisecondsSinceEpoch);
      }

      List<dynamic> cloudTodos = data['todos'] ?? [];
      List<dynamic> cloudCountdowns = data['countdowns'] ?? [];

      // ===========================
      // 4. LWW 合并待办事项 (🚀 坚不可摧的防重复比对算法)
      // ===========================
      if (syncTodos) {
        statusNotifier.value = "正在智能合并待办事项...";

        // 构建云端字典：双保险主键匹配，彻底消灭时区和精度丢失导致的格式漂移
        Map<String, dynamic> cloudTodoByCreatedAt = {};
        for (var t in cloudTodos) {
          if (t['created_at'] != null || t['created_date'] != null) {
            String rawCloudStr = (t['created_at'] ?? t['created_date']).toString();
            cloudTodoByCreatedAt[rawCloudStr] = t;

            // 🚀 备用匹配策略：利用秒级时间戳，防止极端情况下的字符串微秒级精度丢失
            DateTime parsed = _parseCloudTime(rawCloudStr);
            cloudTodoByCreatedAt[(parsed.millisecondsSinceEpoch ~/ 1000).toString()] = t;
          }
        }

        List<TodoItem> todosToRemove = [];

        for (var local in localTodos) {
          try {
            String localIso = local.createdAt.toIso8601String();
            String localSec = (local.createdAt.millisecondsSinceEpoch ~/ 1000).toString();

            // 🚀 寻找分身：先用精准字符串找，找不到再用粗略秒级时间戳兜底
            var cloud = cloudTodoByCreatedAt[localIso] ?? cloudTodoByCreatedAt[localSec];

            if (cloud != null) {
              DateTime cloudTime = _parseCloudTime(cloud['updated_at']);
              bool isCloudDeleted = (cloud['is_deleted'] == 1 || cloud['is_deleted'] == true);

              // 时间戳比对决胜负
              if (cloudTime.isAfter(local.lastUpdated)) {
                if (isCloudDeleted) {
                  todosToRemove.add(local);
                  hasChanges = true;
                } else {
                  local.title = cloud['content'] ?? local.title; // 即使另一台设备修改了名字也能同步过来
                  local.isDone = cloud['is_completed'] == 1 || cloud['is_completed'] == true;
                  local.dueDate = cloud['due_date'] != null ? DateTime.tryParse(cloud['due_date'].toString()) : null;
                  local.lastUpdated = cloudTime;
                  hasChanges = true;
                }
              }
            }
          } catch (e) {
            print("合并待办数据单条异常: $e");
          }
        }
        localTodos.removeWhere((t) => todosToRemove.contains(t));

        // 处理云端完全新增的数据
        for (var cloud in cloudTodos) {
          try {
            bool isCloudDeleted = (cloud['is_deleted'] == 1 || cloud['is_deleted'] == true);
            String cloudRawStr = (cloud['created_at'] ?? cloud['created_date'])?.toString() ?? '';
            DateTime cloudCreatedAt = _parseCloudTime(cloudRawStr);
            String cloudSecStr = (cloudCreatedAt.millisecondsSinceEpoch ~/ 1000).toString();

            // 🚀 严格排重检验：确保本地真的没有任何形式的此待办的旧数据残留
            bool existsLocally = localTodos.any((l) {
              return l.createdAt.toIso8601String() == cloudRawStr ||
                  (l.createdAt.millisecondsSinceEpoch ~/ 1000).toString() == cloudSecStr;
            });

            if (!isCloudDeleted && cloud['content'] != null && !existsLocally) {
              localTodos.add(TodoItem(
                id: const Uuid().v4(), // 本地依然生成离线 UUID 供 UI 组件使用，但不用来跟后端通信
                title: cloud['content'],
                isDone: cloud['is_completed'] == 1 || cloud['is_completed'] == true,
                lastUpdated: _parseCloudTime(cloud['updated_at']),
                recurrence: RecurrenceType.none,
                dueDate: cloud['due_date'] != null ? DateTime.tryParse(cloud['due_date'].toString()) : null,
                createdAt: cloudCreatedAt, // 将云端分配的时间原封不动地接下来
              ));
              hasChanges = true;
            }
          } catch (e) { print("解析云端新增待办异常: $e"); }
        }
      }

      // ===========================
      // 5. LWW 合并倒计时
      // ===========================
      if (syncCountdowns) {
        statusNotifier.value = "正在智能合并倒计时...";

        Map<String, dynamic> cloudCdMap = { for (var c in cloudCountdowns) if (c['title'] != null) c['title']: c };
        List<CountdownItem> cdsToRemove = [];

        for (var local in localCountdowns) {
          try {
            if (cloudCdMap.containsKey(local.title)) {
              var cloud = cloudCdMap[local.title];
              DateTime cloudTime = _parseCloudTime(cloud['updated_at']);
              bool isCloudDeleted = (cloud['is_deleted'] == 1 || cloud['is_deleted'] == true);

              if (cloudTime.isAfter(local.lastUpdated)) {
                if (isCloudDeleted) {
                  cdsToRemove.add(local);
                  hasChanges = true;
                } else {
                  local.targetDate = DateTime.tryParse(cloud['target_time']?.toString() ?? '') ?? local.targetDate;
                  local.lastUpdated = cloudTime;
                  hasChanges = true;
                }
              }
            }
          } catch (e) {
            print("合并倒计时单条异常: $e");
          }
        }
        localCountdowns.removeWhere((item) => cdsToRemove.contains(item));

        for (var cloud in cloudCountdowns) {
          try {
            bool isCloudDeleted = (cloud['is_deleted'] == 1 || cloud['is_deleted'] == true);
            if (!isCloudDeleted && cloud['title'] != null && !localCountdowns.any((l) => l.title == cloud['title'])) {
              localCountdowns.add(CountdownItem(
                title: cloud['title'],
                targetDate: DateTime.tryParse(cloud['target_time']?.toString() ?? '') ?? DateTime.now(),
                lastUpdated: _parseCloudTime(cloud['updated_at']),
              ));
              hasChanges = true;
            }
          } catch (e) { print("解析云端新增倒计时异常: $e"); }
        }
      }

      statusNotifier.value = "正在保存合并结果...";

      // 6. 保存最终结果
      if (hasChanges){
        if (syncTodos) await saveTodos(username, localTodos, sync: false);
        if (syncCountdowns) await saveCountdowns(username, localCountdowns, sync: false);
      }

      statusNotifier.value = "同步完成！";
      // 停留短暂时间让用户看到"同步完成"
      if (context != null) await Future.delayed(const Duration(milliseconds: 400));

    } catch (e) {
      print("全局同步异常中断: $e");
      if (context != null && context.mounted && !dialogClosed) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogClosed = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("同步异常: $e")));
      }
      rethrow;
    } finally {
      _isSyncing = false;
      if (context != null && context.mounted && !dialogClosed) {
        Navigator.of(context, rootNavigator: true).pop(); // 🚀 安全关掉弹窗
        dialogClosed = true;
      }
    }

    return hasChanges;
  }

  static DateTime _parseCloudTime(dynamic timeData) {
    if (timeData == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (timeData is int) return DateTime.fromMillisecondsSinceEpoch(timeData);
    if (timeData is double) return DateTime.fromMillisecondsSinceEpoch(timeData.toInt());
    if (timeData is String) {
      int? parsedInt = int.tryParse(timeData);
      if (parsedInt != null) return DateTime.fromMillisecondsSinceEpoch(parsedInt);

      return DateTime.tryParse(timeData)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // 通用设置项读取与存储
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

  // 新增：便捷获取学期进度设置
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