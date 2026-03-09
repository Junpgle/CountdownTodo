import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // ⚠️ 请替换为你部署后的 Worker URL
  static const String baseUrl = "https://mathquiz.junpgle.me";

  // 🛡️ 内存中持有最新 Token
  static String? _authToken;

  static void setToken(String token) {
    _authToken = token;
  }

  // 统一构建安全 Header
  static Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_authToken != null && _authToken!.isNotEmpty)
        'Authorization': 'Bearer $_authToken',
    };
  }

  // ==========================================
  // 1. 用户认证 (Auth)
  // ==========================================

  static Future<Map<String, dynamic>> register(String username, String email, String password, {String? code}) async {
    try {
      final Map<String, dynamic> bodyMap = {
        'username': username,
        'email': email,
        'password': password,
      };

      if (code != null && code.isNotEmpty) bodyMap['code'] = code;

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
        return {
          'success': true,
          'user': data['user'],
          'token': data['token']
        };
      } else {
        return {'success': false, 'message': data['error'] ?? '登录失败'};
      }
    } catch (e) {
      return {'success': false, 'message': "网络错误: $e"};
    }
  }

  static Future<Map<String, dynamic>> changePassword(int userId, String oldPassword, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/change_password'),
        headers: _getHeaders(),
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
        headers: _getHeaders(),
        body: jsonEncode({'user_id': userId, 'username': username, 'score': score, 'duration': duration}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  // ==========================================
  // 🚀 3. 全新 Delta Sync 增量同步引擎 (替代旧版单条CRUD)
  // ==========================================
  static Future<Map<String, dynamic>> postDeltaSync({
    required int userId,
    required int lastSyncTime,
    required String deviceId,
    required List<Map<String, dynamic>> todosChanges,
    required List<Map<String, dynamic>> countdownsChanges,
    Map<String, dynamic>? screenTime,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'user_id': userId,
        'last_sync_time': lastSyncTime,
        'device_id': deviceId,
        'todos': todosChanges,
        'countdowns': countdownsChanges,
      };

      if (screenTime != null) {
        body['screen_time'] = screenTime;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/sync'),
        headers: _getHeaders(),
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'server_todos': data['server_todos'] ?? [],
          'server_countdowns': data['server_countdowns'] ?? [],
          'new_sync_time': data['new_sync_time'],
          'status': data['status'],
        };
      } else if (response.statusCode == 429) {
        return {
          'success': false,
          'message': data['error'] ?? '今日同步次数已达上限',
          'isLimitExceeded': true,
        };
      } else {
        return {
          'success': false,
          'message': data['error'] ?? '同步失败'
        };
      }
    } catch (e) {
      return {'success': false, 'message': "网络异常: $e"};
    }
  }

  // ==========================================
  // 4. 屏幕使用时间 (Screen Time)
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
        headers: _getHeaders(),
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
      final response = await http.get(Uri.parse('$baseUrl/api/screen_time?user_id=$userId&date=$date'), headers: _getHeaders());
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) { return []; }
  }

  // ==========================================
  // 5. 调试工具 (Debug Tools)
  // ==========================================

  static Future<Map<String, dynamic>> debugResetDatabase() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/debug/reset_database'),
        headers: _getHeaders(),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==========================================
  // 6. 分类映射 (Category Mappings)
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
  // 7. 课表同步 (Courses)
  // ==========================================

  static Future<List<dynamic>> fetchCourses(int userId, {String semester = "default"}) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/courses?user_id=$userId&semester=$semester'),
          headers: _getHeaders()
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> uploadCourses({
    required int userId,
    required List<Map<String, dynamic>> courses,
    String semester = "default",
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/courses'),
        headers: _getHeaders(),
        body: jsonEncode({
          'user_id': userId,
          'semester': semester,
          'courses': courses,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? '课表同步成功'
        };
      }
      else if (response.statusCode == 429) {
        return {
          'success': false,
          'message': data['error'] ?? '今日同步次数已达上限',
          'isLimitExceeded': true,
        };
      }
      else {
        return {
          'success': false,
          'message': data['error'] ?? '课表同步失败'
        };
      }
    } catch (e) {
      return {'success': false, 'message': '网络异常: $e'};
    }
  }

  // ==========================================
  // 7b. 用户设置同步 (semester dates)
  // ==========================================

  /// 上传开学/放假时间到云端（毫秒时间戳，null 表示清除）
  static Future<bool> uploadUserSettings({
    required int? semesterStartMs,
    required int? semesterEndMs,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/settings'),
        headers: _getHeaders(),
        body: jsonEncode({
          'semester_start': semesterStartMs,
          'semester_end': semesterEndMs,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 从云端拉取开学/放假时间（返回毫秒时间戳，null 表示未设置）
  static Future<Map<String, dynamic>?> fetchUserSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/settings'),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ==========================================
  // 8. 番茄钟 (Pomodoro)
  // ==========================================

  /// 拉取用户标签（含已删除，供 LWW 合并）
  static Future<List<dynamic>> fetchPomodoroTags() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/pomodoro/tags'),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) { return []; }
  }

  /// 上传/同步标签到云端（Delta Sync）
  static Future<bool> syncPomodoroTags(List<Map<String, dynamic>> tags) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pomodoro/tags'),
        headers: _getHeaders(),
        body: jsonEncode({'tags': tags}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  /// 上传单条专注记录（对齐 pomodoro_records 表）
  static Future<bool> uploadPomodoroRecord(Map<String, dynamic> record) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pomodoro/records'),
        headers: _getHeaders(),
        body: jsonEncode({'record': record}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  /// 批量上传专注记录
  static Future<bool> uploadPomodoroRecords(List<Map<String, dynamic>> records) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pomodoro/records'),
        headers: _getHeaders(),
        body: jsonEncode({'records': records}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  /// 拉取专注记录（按时间范围）
  static Future<List<dynamic>> fetchPomodoroRecords({int? fromMs, int? toMs}) async {
    try {
      final params = <String, String>{};
      if (fromMs != null) params['from'] = fromMs.toString();
      if (toMs != null)   params['to']   = toMs.toString();
      final uri = Uri.parse('$baseUrl/api/pomodoro/records')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _getHeaders());
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) { return []; }
  }

  /// 同步番茄钟设置到云端
  static Future<bool> syncPomodoroSettings(Map<String, dynamic> settings) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pomodoro/settings'),
        headers: _getHeaders(),
        body: jsonEncode(settings),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  /// 拉取番茄钟设置
  static Future<Map<String, dynamic>?> fetchPomodoroSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/pomodoro/settings'),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return null;
    } catch (e) { return null; }
  }

  /// 查询其他设备是否有正在进行的专注（跨端感知）
  static Future<Map<String, dynamic>?> fetchActivePomodoroFromOtherDevice(String currentDeviceId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pomodoro/active')
          .replace(queryParameters: {'device_id': currentDeviceId});
      final response = await http.get(uri, headers: _getHeaders());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['active'] == true) return data['record'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) { return null; }
  }

  // 向后兼容旧方法名
  static Future<bool> uploadPomodoroSessions(List<Map<String, dynamic>> sessions) =>
      uploadPomodoroRecords(sessions);
  static Future<List<dynamic>> fetchPomodoroSessions({int? fromMs, int? toMs}) =>
      fetchPomodoroRecords(fromMs: fromMs, toMs: toMs);
}