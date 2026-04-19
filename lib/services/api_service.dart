import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class ApiService {
  static String baseUrl = "https://mathquiz.junpgle.me";
  static const String cloudflareUrl = 'https://mathquiz.junpgle.me';
  static const String aliyunProdUrl = 'http://101.200.13.100:8082';
  static const String aliyunTestUrl = 'http://101.200.13.100:8084';
  static String? _baseUrlOverride;

  // 🛡️ 全局使用的、跳过 SSL 证书验证的 HTTP 客户端
  static http.Client? _clientInstance;
  static http.Client get _client {
    _clientInstance ??= IOClient(
      HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true,
    );
    return _clientInstance!;
  }

  // 🛡️ 内存中持有最新 Token
  static String? _authToken;

  static void setToken(String token) {
    _authToken = token;
  }

  static int currentUserId = 0;


  // 🚀 公开获取 token 的方法（供 WebSocket 等服务使用）
  static String? getToken() => _authToken;

  static bool _isLocked = false;

  // 🚀 强制锁定环境地址（在 EnvironmentService 中调用）
  static void lockBaseUrl(String url) {
    baseUrl = url;
    _isLocked = true;
  }

  // 初始化设置
  static void setServerChoice(String choice) {
    if (_isLocked) return; // 🛡️ 如果环境已锁定（如测试版），禁止通过设置更改地址
    
    if (choice == 'aliyun') {
      baseUrl = aliyunProdUrl;
    } else {
      baseUrl = cloudflareUrl;
    }
  }

  // --- Migration Tool Support ---
  static void setBaseUrlOverride(String url) {
    _baseUrlOverride = url;
  }

  static void clearBaseUrlOverride() {
    _baseUrlOverride = null;
  }

  static String get _effectiveBaseUrl => _baseUrlOverride ?? baseUrl;
  // -----------------------------

  // 统一构建安全 Header
  static Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_authToken != null && _authToken!.isNotEmpty)
        'Authorization': 'Bearer $_authToken',
    };
  }

  /// 🚀 链路健康检查：探测服务器是否在线
  static Future<bool> ping() async {
    try {
      // 访问基础路径，只要有任何响应（即使是 404）也说明网络通畅且服务器在线
      final response = await _client.get(
        Uri.parse('$_effectiveBaseUrl/'),
      ).timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      // 网络超时、Socket 错误等均视为离线
      return false;
    }
  }

  // ==========================================
  // 1. 用户认证 (Auth)
  // ==========================================

  static Future<Map<String, dynamic>> register(
      String username, String email, String password,
      {String? code}) async {
    try {
      final Map<String, dynamic> bodyMap = {
        'username': username,
        'email': email,
        'password': password,
      };

      if (code != null && code.isNotEmpty) bodyMap['code'] = code;

      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/auth/register'),
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

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        if (data['user'] != null && data['user']['id'] != null) {
          currentUserId = data['user']['id'];
        }
        return {'success': true, 'user': data['user'], 'token': data['token']};
      } else {
        return {'success': false, 'message': data['error'] ?? '登录失败'};
      }

    } catch (e) {
      return {'success': false, 'message': "网络错误: $e"};
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/auth/forgot_password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message'] ?? data['error'] ?? '发送失败',
      };
    } catch (e) {
      return {'success': false, 'message': "网络错误: $e"};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(
      String email, String code, String newPassword) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/auth/reset_password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'new_password': newPassword,
        }),
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message'] ?? data['error'] ?? '重置失败',
      };
    } catch (e) {
      return {'success': false, 'message': "网络错误: $e"};
    }
  }

  static Future<Map<String, dynamic>> changePassword(
      int userId, String oldPassword, String newPassword) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/auth/change_password'),
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
      final response =
          await _client.get(Uri.parse('$_effectiveBaseUrl/api/leaderboard'));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> uploadScore(
      {required int userId,
      required String username,
      required int score,
      required int duration}) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/score'),
        headers: _getHeaders(),
        body: jsonEncode({
          'user_id': userId,
          'username': username,
          'score': score,
          'duration': duration
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // 🚀 3. 全新 Delta Sync 增量同步引擎
  // ==========================================
  static Future<Map<String, dynamic>> postDeltaSync({
    required int userId,
    required int lastSyncTime,
    required String deviceId,
    required List<Map<String, dynamic>> todosChanges,
    required List<Map<String, dynamic>> countdownsChanges,
    List<Map<String, dynamic>> todoGroupsChanges = const [],
    Map<String, dynamic>? screenTime,
    List<Map<String, dynamic>> timeLogsChanges =
        const [], // 🚀 1. 新增命名参数，默认为空列表
  }) async {
    try {
      final Map<String, dynamic> body = {
        'user_id': userId,
        'last_sync_time': lastSyncTime,
        'device_id': deviceId,
        'todos': todosChanges,
        'todo_groups': todoGroupsChanges,
        'countdowns': countdownsChanges,
        'time_logs_changes': timeLogsChanges, // 🚀 2. 将数据加入到 JSON Payload 中
      };

      if (screenTime != null) {
        body['screen_time'] = screenTime;
      }

      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/sync'),
        headers: _getHeaders(),
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // 解析冲突信息
        final List<dynamic> rawConflicts = data['conflicts'] ?? [];

        return {
          'success': true,
          'conflicts': rawConflicts,
          'server_todos': data['server_todos'] ?? [],
          'server_todo_groups': data['server_todo_groups'] ?? [],
          'server_countdowns': data['server_countdowns'] ?? [],
          'new_sync_time': data['new_sync_time'],
          'server_time_logs': data['server_time_logs'] ?? [],
          'status': data['status'],
        };
      } else if (response.statusCode == 429) {
        return {
          'success': false,
          'message': data['error'] ?? '今日同步次数已达上限',
          'isLimitExceeded': true,
        };
      } else {
        return {'success': false, 'message': data['error'] ?? '同步失败'};
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
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/screen_time'),
        headers: _getHeaders(),
        body: jsonEncode({
          'user_id': userId,
          'device_name': deviceName,
          'record_date': date,
          'apps': apps,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> fetchScreenTime(int userId, String date) async {
    try {
      final response = await _client.get(
          Uri.parse(
              '$_effectiveBaseUrl/api/screen_time?user_id=$userId&date=$date'),
          headers: _getHeaders());
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  // ==========================================
  // 5. 调试工具 (Debug Tools)
  // ==========================================

  static Future<Map<String, dynamic>> debugResetDatabase() async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/debug/reset_database'),
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
      final response =
          await _client.get(Uri.parse('$_effectiveBaseUrl/api/mappings'));
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

  static Future<List<dynamic>> fetchCourses(int userId,
      {String semester = "default"}) async {
    try {
      final response = await _client.get(
          Uri.parse(
              '$_effectiveBaseUrl/api/courses?user_id=$userId&semester=$semester'),
          headers: _getHeaders());
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
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/courses'),
        headers: _getHeaders(),
        body: jsonEncode({
          'user_id': userId,
          'semester': semester,
          'courses': courses,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message'] ?? '课表同步成功'};
      } else if (response.statusCode == 429) {
        return {
          'success': false,
          'message': data['error'] ?? '今日同步次数已达上限',
          'isLimitExceeded': true,
        };
      } else {
        return {'success': false, 'message': data['error'] ?? '课表同步失败'};
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
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/settings'),
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
      final response = await _client.get(
        Uri.parse('$_effectiveBaseUrl/api/settings'),
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
  static Future<List<dynamic>> fetchPomodoroTags([int? userId]) async {
    try {
      final String urlPostfix = userId != null ? '?user_id=$userId' : '';
      final response = await _client.get(
        Uri.parse('$_effectiveBaseUrl/api/pomodoro/tags$urlPostfix'),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchTodos(int userId) async {
    try {
      final response = await _client.get(
          Uri.parse('$_effectiveBaseUrl/api/todos?user_id=$userId'),
          headers: _getHeaders());
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchCountdowns(int userId) async {
    try {
      final response = await _client.get(
          Uri.parse('$_effectiveBaseUrl/api/countdowns?user_id=$userId'),
          headers: _getHeaders());
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchTimeLogs(int userId) async {
    try {
      final response = await _client.get(
          Uri.parse('$_effectiveBaseUrl/api/time_logs?user_id=$userId'),
          headers: _getHeaders());
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 上传/同步标签到云端（Delta Sync）
  static Future<bool> syncPomodoroTags(List<Map<String, dynamic>> tags) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/pomodoro/tags'),
        headers: _getHeaders(),
        body: jsonEncode({'tags': tags}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 上传单条专注记录（对齐 pomodoro_records 表）
  static Future<bool> uploadPomodoroRecord(Map<String, dynamic> record) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/pomodoro/records'),
        headers: _getHeaders(),
        body: jsonEncode({'record': record}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> migrationRegister({
    required String email,
    required String username,
    required String password,
    String tier = 'free',
    int? semesterStart,
    int? semesterEnd,
  }) async {
    final response = await _client.post(
      Uri.parse('$_effectiveBaseUrl/api/migrate_register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'username': username,
        'password': password,
        'tier': tier,
        'semester_start': semesterStart,
        'semester_end': semesterEnd
      }),
    );
    return jsonDecode(response.body);
  }

  /// 批量上传专注记录
  static Future<bool> uploadPomodoroRecords(
      List<Map<String, dynamic>> records) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/pomodoro/records'),
        headers: _getHeaders(),
        body: jsonEncode({'records': records}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 拉取专注记录（按时间范围）
  static Future<List<dynamic>> fetchPomodoroRecords(
      [int? userId, int? fromMs, int? toMs]) async {
    try {
      final params = <String, String>{};
      if (userId != null) params['user_id'] = userId.toString();
      if (fromMs != null) params['from'] = fromMs.toString();
      if (toMs != null) params['to'] = toMs.toString();
      final uri = Uri.parse('$_effectiveBaseUrl/api/pomodoro/records')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await _client.get(uri, headers: _getHeaders());
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 同步番茄钟设置到云端
  static Future<bool> syncPomodoroSettings(
      Map<String, dynamic> settings) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/pomodoro/settings'),
        headers: _getHeaders(),
        body: jsonEncode(settings),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 拉取番茄钟设置
  static Future<Map<String, dynamic>?> fetchPomodoroSettings() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/pomodoro/settings'),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 查询其他设备是否有正在进行的专注（跨端感知）
  static Future<Map<String, dynamic>?> fetchActivePomodoroFromOtherDevice(
      String currentDeviceId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pomodoro/active')
          .replace(queryParameters: {'device_id': currentDeviceId});
      final response = await _client.get(uri, headers: _getHeaders());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['active'] == true)
          return data['record'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // 🚀 9. 在线统计与设备版本分布
  // ==========================================

  /// 获取当前在线设备分布统计
  static Future<Map<String, dynamic>?> fetchOnlineStats() async {
    try {
      final response = await _client.get(
        Uri.parse('$_effectiveBaseUrl/api/online_stats'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取所有设备历史版本分布统计（含离线设备）
  static Future<Map<String, dynamic>?> fetchDeviceVersionStats() async {
    try {
      final response = await _client.get(
        Uri.parse('$_effectiveBaseUrl/api/device_version_stats'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 向后兼容旧方法名
  static Future<bool> uploadPomodoroSessions(
          List<Map<String, dynamic>> sessions) =>
      uploadPomodoroRecords(sessions);
  static Future<List<dynamic>> fetchPomodoroSessions(
          {int? fromMs, int? toMs}) =>
      fetchPomodoroRecords(null, fromMs, toMs);

  // ==========================================
  // 👥 10. 团队与协作 (Teams)
  // ==========================================

  static Future<List<dynamic>> fetchTeams() async {
    try {
      final response = await _client.get(Uri.parse('$_effectiveBaseUrl/api/teams'), headers: _getHeaders());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['teams'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> createTeam(String name) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/teams/create'),
        headers: _getHeaders(),
        body: jsonEncode({'name': name}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> generateInviteCode(String teamUuid) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/teams/invite'),
        headers: _getHeaders(),
        body: jsonEncode({'team_uuid': teamUuid}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> addTeamMemberByEmail(String teamUuid, String email) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/teams/members/add'),
        headers: _getHeaders(),
        body: jsonEncode({'team_uuid': teamUuid, 'email': email}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> joinTeamByCode(String code) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/teams/join'),
        headers: _getHeaders(),
        body: jsonEncode({'code': code}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  static Future<Map<String, dynamic>> deleteTeam(String teamUuid) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/teams/delete'),
        headers: _getHeaders(),
        body: jsonEncode({'team_uuid': teamUuid}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> leaveTeam(String teamUuid) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/teams/leave'),
        headers: _getHeaders(),
        body: jsonEncode({'team_uuid': teamUuid}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<dynamic>> fetchTeamMembers(String teamUuid) async {
    try {
      final response = await _client.get(
        Uri.parse('$_effectiveBaseUrl/api/teams/members?team_uuid=$teamUuid'),
        headers: _getHeaders(),
      );
      final data = jsonDecode(response.body);
      return data['members'] ?? [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> removeTeamMember(String teamUuid, int targetUserId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_effectiveBaseUrl/api/teams/members/remove'),
        headers: _getHeaders(),
        body: jsonEncode({'team_uuid': teamUuid, 'target_user_id': targetUserId}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
