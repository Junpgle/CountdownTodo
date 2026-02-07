import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // ⚠️ 请替换为你部署后的 Worker URL
  static const String baseUrl = "https://mathquiz.junpgle.me";

  // ==========================================
  // 1. 用户认证 (Auth)
  // ==========================================

  // 注册 (支持两步验证)
  // 第一次调用：不传 code -> 后端发送邮件，返回 {require_verify: true}
  // 第二次调用：传 code -> 后端验证并创建账号
  static Future<Map<String, dynamic>> register(String username, String email, String password, {String? code}) async {
    try {
      final Map<String, dynamic> bodyMap = {
        'username': username,
        'email': email,
        'password': password,
      };

      // 如果有验证码，带上验证码
      if (code != null && code.isNotEmpty) {
        bodyMap['code'] = code;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyMap),
      );

      final data = jsonDecode(response.body);

      // 将 HTTP 状态码也纳入判断
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
          'require_verify': data['require_verify'] ?? false, // 关键字段
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

  // ... (其余排行榜、待办、倒计时方法保持不变，省略以节省空间) ...

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
    } catch (e) { return []; }
  }

  static Future<bool> addTodo(int userId, String content) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/todos'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'user_id': userId, 'content': content}));
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<bool> toggleTodo(int todoId, bool isCompleted) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/todos/toggle'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'id': todoId, 'is_completed': isCompleted}));
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<bool> deleteTodo(int todoId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/todos'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'id': todoId}));
      return response.statusCode == 200;
    } catch (e) { return false; }
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

  static Future<bool> addCountdown(int userId, String title, DateTime targetTime) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/countdowns'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'user_id': userId, 'title': title, 'target_time': targetTime.toIso8601String()}));
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<bool> deleteCountdown(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/countdowns'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'id': id}));
      return response.statusCode == 200;
    } catch (e) { return false; }
  }
}