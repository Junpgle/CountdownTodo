import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class StorageService {
  static const String KEY_USERS = "users_data";
  static const String KEY_LEADERBOARD = "leaderboard_data";
  static const String KEY_SETTINGS = "quiz_settings"; // 新增配置Key

  // 注册用户
  static Future<bool> register(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> users = {};

    String? usersJson = prefs.getString(KEY_USERS);
    if (usersJson != null) {
      users = jsonDecode(usersJson);
    }

    if (users.containsKey(username)) {
      return false; // 用户已存在
    }

    users[username] = password;
    await prefs.setString(KEY_USERS, jsonEncode(users));
    return true;
  }

  // 登录验证
  static Future<bool> login(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    String? usersJson = prefs.getString(KEY_USERS);
    if (usersJson == null) return false;

    Map<String, dynamic> users = jsonDecode(usersJson);
    return users.containsKey(username) && users[username] == password;
  }

  // 保存测试记录 (历史记录)
  static Future<void> saveHistory(String username, int score, int duration, String details) async {
    final prefs = await SharedPreferences.getInstance();
    String key = "history_$username";
    List<String> history = prefs.getStringList(key) ?? [];

    String timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    String record = "时间: $timeStr\n得分: $score\n用时: ${duration}秒\n详情:\n$details\n-----------------";

    history.insert(0, record); // 最新记录插在最前
    await prefs.setStringList(key, history);
  }

  // 获取用户历史
  static Future<List<String>> getHistory(String username) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList("history_$username") ?? [];
  }

  // 更新排行榜
  static Future<void> updateLeaderboard(String username, int score, int duration) async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> list = [];

    String? jsonStr = prefs.getString(KEY_LEADERBOARD);
    if (jsonStr != null) {
      list = jsonDecode(jsonStr);
    }

    list.add({
      'username': username,
      'score': score,
      'time': duration,
    });

    // 排序：分数高优先，分数相同时间短优先
    list.sort((a, b) {
      if (a['score'] != b['score']) {
        return b['score'].compareTo(a['score']); // 降序
      }
      return a['time'].compareTo(b['time']); // 升序
    });

    // 只保留前10
    if (list.length > 10) list = list.sublist(0, 10);

    await prefs.setString(KEY_LEADERBOARD, jsonEncode(list));
  }

  // 获取排行榜
  static Future<List<Map<String, dynamic>>> getLeaderboard() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(KEY_LEADERBOARD);
    if (jsonStr == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
  }

  // --- 新增: 设置相关方法 ---

  // 保存设置
  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_SETTINGS, jsonEncode(settings));
  }

  // 获取设置 (带默认值)
  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(KEY_SETTINGS);

    if (jsonStr != null) {
      return Map<String, dynamic>.from(jsonDecode(jsonStr));
    }

    // 默认设置
    return {
      'operators': ['+', '-'], // 默认加减
      'min_num1': 0, 'max_num1': 50,
      'min_num2': 0, 'max_num2': 50,
      'max_result': 100,
    };
  }
}