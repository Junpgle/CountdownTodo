import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // ⚠️ 请替换为你部署后的 Worker URL
  static const String baseUrl = "https://mathquiz.junpgle.me";

  // ==========================================
  // 1. 用户认证 (Auth)
  // ==========================================

  // 注册 (支持两步验证)
  static Future<Map<String, dynamic>> register(String username, String email, String password, {String? code}) async {
    try {
      final Map<String, dynamic> bodyMap = {
        'username': username,
        'email': email,
        'password': password,
      };

      if (code != null && code.isNotEmpty) {
        bodyMap['code'] = code;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyMap),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
          'require_verify': data['require_verify'] ?? false,
        };
      } else {
        return {'success': false, 'message': data['error'] ?? '注册失败'};
      }
    } catch (e) {
      return {'success': false, 'message': "网络错误: $e"};
    }
  }

  // 登录
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'user': data['user']};
      } else {
        return {'success': false, 'message': data['error'] ?? '登录失败'};
      }
    } catch (e) {
      return {'success': false, 'message': "网络错误: $e"};
    }
  }

  // 修改密码
  static Future<Map<String, dynamic>> changePassword(int userId, String oldPassword, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/change_password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message'] ?? data['error'] ?? '修改失败'
      };
    } catch (e) {
      return {'success': false, 'message': "网络错误: $e"};
    }
  }

  // ==========================================
  // 2. 排行榜 (Leaderboard)
  // ==========================================
  static Future<List<dynamic>> fetchLeaderboard() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/leaderboard'));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) { return []; }
  }

  static Future<bool> uploadScore({required int userId, required String username, required int score, required int duration}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/score'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'username': username, 'score': score, 'duration': duration}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  // ==========================================
  // 3. 待办事项 (Todos)
  // ==========================================

  static Future<List<dynamic>> fetchTodos(int userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/todos?user_id=$userId'));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> addTodo(int userId, String content, {bool isCompleted = false, int? timestamp, String? dueDate, String? createdDate}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/todos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'content': content,
          'is_completed': isCompleted,
          'client_updated_at': timestamp ?? DateTime.now().millisecondsSinceEpoch,
          'due_date': dueDate,
          'created_date': createdDate,
        }),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<bool> toggleTodo(int id, bool isCompleted) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/todos/toggle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'is_completed': isCompleted}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteTodo(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/todos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // 4. 倒计时 (Countdowns)
  // ==========================================

  static Future<List<dynamic>> fetchCountdowns(int userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/countdowns?user_id=$userId'));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) { return []; }
  }

  static Future<bool> addCountdown(int userId, String title, DateTime targetTime, int lastUpdatedMs) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/countdowns'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'title': title,
          'target_time': targetTime.toIso8601String(),
          'client_updated_at': lastUpdatedMs,
        }),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<bool> deleteCountdown(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/countdowns'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': id,
          'client_updated_at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // 5. 屏幕使用时间 (Screen Time)
  // ==========================================

  static Future<bool> uploadScreenTime({
    required int userId,
    required String deviceName,
    required String date,
    required List<Map<String, dynamic>> apps,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/screen_time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'device_name': deviceName,
          'record_date': date,
          'apps': apps,
        }),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<List<dynamic>> fetchScreenTime(int userId, String date) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/screen_time?user_id=$userId&date=$date'));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) { return []; }
  }

  // ==========================================
  // 6. 调试工具 (Debug Tools)
  // ==========================================

  static Future<Map<String, dynamic>> debugResetDatabase() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/debug/reset_database'),
        headers: {'Content-Type': 'application/json'},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==========================================
  // 7. 分类映射 (Category Mappings)
  // ==========================================

  static Future<List<dynamic>> fetchAppMappings() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/mappings'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  // ==========================================
  // 🚀 8. 全局聚合同步 (Sync All) - 节省网络请求次数
  // ==========================================

  static Future<Map<String, dynamic>> syncAll({
    required int userId,
    required List<Map<String, dynamic>> todos,
    required List<Map<String, dynamic>> countdowns,
    Map<String, dynamic>? screenTime,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'user_id': userId,
        'todos': todos,
        'countdowns': countdowns,
      };

      if (screenTime != null) {
        body['screen_time'] = screenTime;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/sync_all'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      // 请求成功处理
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'], // 包含后端返回的最新 todos 和 countdowns 列表
          'message': data['message'] ?? '同步成功'
        };
      }
      // 拦截 429 频率超限
      else if (response.statusCode == 429) {
        return {
          'success': false,
          'message': data['error'] ?? '今日同步次数已达上限',
          'isLimitExceeded': true, // 额外标记用于 UI 层判断并弹窗
        };
      }
      // 其他错误
      else {
        return {
          'success': false,
          'message': data['error'] ?? '同步失败'
        };
      }
    } catch (e) {
      return {'success': false, 'message': "网络异常: $e"};
    }
  }
}