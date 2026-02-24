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

  /// 获取待办列表 (后端会自动过滤 is_deleted = 0)
  static Future<List<dynamic>> fetchTodos(int userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/todos?user_id=$userId'));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> addTodo(int userId, String content) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/todos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'content': content}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 切换完成状态
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

  /// 删除待办 (后端执行软删除)
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
  // 4. 倒计时 (Countdowns) - 引入时间戳覆盖逻辑
  // ==========================================

  /// 获取倒计时列表
  static Future<List<dynamic>> fetchCountdowns(int userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/countdowns?user_id=$userId'));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) { return []; }
  }

  /// 添加或更新倒计时 (Last Write Wins)
  /// 如果同一 user 下已存在相同 title，后端将根据时间戳决定是否覆盖
  static Future<bool> addCountdown(int userId, String title, DateTime targetTime) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/countdowns'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'title': title,
          'target_time': targetTime.toIso8601String(),
          // 发送本地当前时间戳作为修改版本
          'client_updated_at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      // 返回 success: true 并不代表一定写入（可能云端更旧被忽略），但逻辑上同步请求已成功处理
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 删除倒计时
  static Future<bool> deleteCountdown(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/countdowns'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': id,
          // 删除也携带时间戳，确保该“删除操作”是针对特定版本的
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

  // 在 ApiService 类中添加

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

}

