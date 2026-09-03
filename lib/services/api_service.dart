import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'http_client_factory.dart';
import '../storage_service.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String cloudflareUrl = 'https://mathquiz.junpgle.me';
  static const String webAliyunProxyUrl = 'https://api-cdt.junpgle.me';
  static const String aliyunProdUrl = 'http://101.200.13.100:8082';
  static const String aliyunTestUrl = 'http://101.200.13.100:8084';

  // Web must never start against the retired Cloudflare Worker. Share pages
  // intentionally skip the normal app initialization sequence, so the
  // default must already be the current API proxy before the first request.
  static String baseUrl = kIsWeb ? webAliyunProxyUrl : cloudflareUrl;
  static String? _baseUrlOverride;

  // 🛡️ 全局使用的、跳过 SSL 证书验证的 HTTP 客户端
  static http.Client? _clientInstance;
  static http.Client? _deltaSyncClient;
  static http.Client get _client {
    _clientInstance ??= createApiHttpClient();
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

    if (kIsWeb) {
      baseUrl = webAliyunProxyUrl;
      return;
    }

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

  // Web 分享页必须始终走当前 Alibaba Zero Trust 代理。环境初始化、旧版
  // 本地设置或迁移工具都不应把浏览器请求重新指向已弃用的 Worker。
  static String get _effectiveBaseUrl =>
      kIsWeb ? webAliyunProxyUrl : (_baseUrlOverride ?? baseUrl);
  static String get effectiveBaseUrl => _effectiveBaseUrl;

  /// Stable namespace for sync watermarks. Test/custom endpoints must not
  /// share the production or Cloudflare watermark.
  static String get syncServerKey {
    final normalized = _effectiveBaseUrl.replaceFirst(RegExp(r'/$'), '');
    if (normalized == aliyunProdUrl) return 'aliyun';
    if (normalized == aliyunTestUrl) return 'aliyun_test';
    if (normalized == cloudflareUrl || normalized == webAliyunProxyUrl) {
      return 'cf';
    }
    return 'custom_${base64Url.encode(utf8.encode(normalized)).replaceAll('=', '')}';
  }

  static bool get isTestServer => _effectiveBaseUrl.contains(':8084');
  // -----------------------------

  // 统一构建安全 Header
  static Map<String, String> _getHeaders({bool includeAuth = true}) {
    return {
      'Content-Type': 'application/json',
      if (includeAuth && _authToken != null && _authToken!.isNotEmpty)
        'Authorization': 'Bearer $_authToken',
    };
  }

  /// 统一构造 API 请求，避免各接口重复处理 Base URL、Header、JSON body
  /// 和超时。接口方法仍负责解释状态码和响应数据。
  static Future<http.Response> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
    bool includeAuth = true,
    http.Client? client,
  }) async {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = path.startsWith('http://') || path.startsWith('https://')
        ? Uri.parse(path)
        : Uri.parse('$_effectiveBaseUrl$normalizedPath');
    final requestHeaders = headers ?? _getHeaders(includeAuth: includeAuth);
    final encodedBody = body == null
        ? null
        : body is String
            ? body
            : jsonEncode(body);

    final requestClient = client ?? _client;
    late Future<http.Response> responseFuture;
    switch (method.toUpperCase()) {
      case 'GET':
        responseFuture = requestClient.get(uri, headers: requestHeaders);
      case 'POST':
        responseFuture = requestClient.post(
          uri,
          headers: requestHeaders,
          body: encodedBody,
        );
      case 'PUT':
        responseFuture = requestClient.put(
          uri,
          headers: requestHeaders,
          body: encodedBody,
        );
      case 'DELETE':
        responseFuture = requestClient.delete(
          uri,
          headers: requestHeaders,
          body: encodedBody,
        );
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }

    return timeout == null ? responseFuture : responseFuture.timeout(timeout);
  }

  /// Best-effort cancellation for the combined delta-sync request. Closing the
  /// dedicated client prevents a finance opt-out from leaving a request in
  /// flight; already-processed server data cannot be recalled.
  static void cancelDeltaSyncRequest() {
    _deltaSyncClient?.close();
    _deltaSyncClient = null;
  }

  /// 🚀 链路健康检查：探测服务器是否在线
  static Future<bool> ping() async {
    try {
      // 访问基础路径，只要有任何响应（即使是 404）也说明网络通畅且服务器在线
      await _request(
        'GET',
        '/',
        timeout: const Duration(seconds: 5),
        includeAuth: false,
      );
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
      {String? code, String? turnstileToken}) async {
    try {
      final Map<String, dynamic> bodyMap = {
        'username': username,
        'email': email,
        'password': password,
      };

      if (code != null && code.isNotEmpty) bodyMap['code'] = code;
      if (turnstileToken != null && turnstileToken.isNotEmpty) {
        bodyMap['turnstile_token'] = turnstileToken;
      }

      final response = await _request(
        'POST',
        '/api/auth/register',
        body: bodyMap,
        includeAuth: false,
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

  static Future<Map<String, dynamic>> login(String email, String password,
      {String? turnstileToken}) async {
    try {
      final Map<String, dynamic> bodyMap = {
        'email': email,
        'password': password,
      };

      if (turnstileToken != null && turnstileToken.isNotEmpty) {
        bodyMap['turnstile_token'] = turnstileToken;
      }

      final response = await _request(
        'POST',
        '/api/auth/login',
        body: bodyMap,
        includeAuth: false,
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
      final response = await _request(
        'POST',
        '/api/auth/forgot_password',
        body: {'email': email},
        includeAuth: false,
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
      final response = await _request(
        'POST',
        '/api/auth/reset_password',
        body: {
          'email': email,
          'code': code,
          'new_password': newPassword,
        },
        includeAuth: false,
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
      final response = await _request(
        'POST',
        '/api/auth/change_password',
        body: {
          'user_id': userId,
          'old_password': oldPassword,
          'new_password': newPassword,
        },
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
      final response = await _request(
        'GET',
        '/api/leaderboard',
        includeAuth: false,
      );
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
      final response = await _request(
        'POST',
        '/api/score',
        body: {
          'user_id': userId,
          'username': username,
          'score': score,
          'duration': duration
        },
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
    bool forceFullSync = false,
    List<Map<String, dynamic>> timeLogsChanges = const [],
    List<Map<String, dynamic>> planBlocksChanges = const [],
    List<Map<String, dynamic>> fixedSchedulesChanges = const [],
    bool fixedSchedulesFullSync = false,
    List<Map<String, dynamic>> pomodoroChanges = const [],
    List<Map<String, dynamic>> tagChanges = const [],
    List<Map<String, dynamic>> habitGoalsChanges = const [],
    List<Map<String, dynamic>> habitRuleChanges = const [],
    List<Map<String, dynamic>> habitCheckInChanges = const [],
    List<Map<String, dynamic>> habitSleepCoachingPlanChanges = const [],
    bool habitFullSync = false,
    int? habitLastSyncTime,
    bool syncHabits = true,
    List<Map<String, dynamic>> financeCategoryChanges = const [],
    List<Map<String, dynamic>> financePaymentMethodChanges = const [],
    List<Map<String, dynamic>> financeTransactionChanges = const [],
    List<Map<String, dynamic>> financeLoanChanges = const [],
    List<Map<String, dynamic>> financeLoanInstallmentChanges = const [],
    List<Map<String, dynamic>> financeBudgetChanges = const [],
    List<Map<String, dynamic>> financeRecurringRuleChanges = const [],
    List<Map<String, dynamic>> financeTemplateChanges = const [],
    bool financeFullSync = false,
    int? financeLastSyncTime,
    bool syncFinance = true,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'user_id': userId,
        'last_sync_time': lastSyncTime,
        'device_id': deviceId,
        'todos': todosChanges,
        'todo_groups': todoGroupsChanges,
        'countdowns': countdownsChanges,
        'time_logs_changes': timeLogsChanges,
        'todo_plan_blocks_changes': planBlocksChanges,
        'fixed_schedules_changes': fixedSchedulesChanges,
        'fixed_schedules_full_sync': fixedSchedulesFullSync,
        'pomodoro_records_changes': pomodoroChanges,
        'pomodoro_tags_changes': tagChanges,
        'habit_goals_changes': habitGoalsChanges,
        'habit_goal_rules_changes': habitRuleChanges,
        'habit_checkins_changes': habitCheckInChanges,
        'habit_sleep_coaching_plans_changes': habitSleepCoachingPlanChanges,
        'habit_full_sync': habitFullSync,
        'sync_habits': syncHabits,
        'finance_categories_changes': financeCategoryChanges,
        'finance_payment_methods_changes': financePaymentMethodChanges,
        'finance_transactions_changes': financeTransactionChanges,
        'finance_loans_changes': financeLoanChanges,
        'finance_loan_installments_changes': financeLoanInstallmentChanges,
        'finance_budgets_changes': financeBudgetChanges,
        'finance_recurring_rules_changes': financeRecurringRuleChanges,
        'finance_entry_templates_changes': financeTemplateChanges,
        'finance_full_sync': financeFullSync,
        'sync_finance': syncFinance,
        'force_full_sync': forceFullSync,
      };

      if (habitLastSyncTime != null) {
        body['habit_last_sync_time'] = habitLastSyncTime;
      }

      if (financeLastSyncTime != null) {
        body['finance_last_sync_time'] = financeLastSyncTime;
      }

      if (screenTime != null) {
        body['screen_time'] = screenTime;
      }

      final syncClient = createApiHttpClient();
      _deltaSyncClient?.close();
      _deltaSyncClient = syncClient;
      late final http.Response response;
      try {
        response = await _request(
          'POST',
          '/api/sync',
          body: body,
          client: syncClient,
        );
      } finally {
        if (identical(_deltaSyncClient, syncClient)) {
          _deltaSyncClient = null;
        }
        syncClient.close();
      }

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
          'server_pomodoros': data['server_pomodoro_records'] ?? [],
          'server_tags': data['server_pomodoro_tags'] ?? [],
          'server_plan_blocks': data['server_plan_blocks'] ?? [],
          'server_fixed_schedules': data['server_fixed_schedules'] ?? [],
          'server_habit_goals': data['server_habit_goals'] ?? [],
          'server_habit_goal_rules': data['server_habit_goal_rules'] ?? [],
          'server_habit_checkins': data['server_habit_checkins'] ?? [],
          'server_habit_sleep_coaching_plans':
              data['server_habit_sleep_coaching_plans'] ?? [],
          'new_habit_sync_time': data['new_habit_sync_time'],
          'server_finance_categories': data['server_finance_categories'] ?? [],
          'server_finance_payment_methods':
              data['server_finance_payment_methods'] ?? [],
          'server_finance_transactions':
              data['server_finance_transactions'] ?? [],
          // Keep these nullable so a finance_v1 server that predates the
          // loan tables cannot be mistaken for an empty loan snapshot.
          'server_finance_loans': data['server_finance_loans'],
          'server_finance_loan_installments':
              data['server_finance_loan_installments'],
          'server_finance_budgets': data['server_finance_budgets'] ?? [],
          'server_finance_recurring_rules':
              data['server_finance_recurring_rules'] ?? [],
          'server_finance_entry_templates':
              data['server_finance_entry_templates'] ?? [],
          'new_finance_sync_time': data['new_finance_sync_time'],
          // Keep a missing acknowledgement field distinguishable from an
          // empty acknowledgement list. This prevents a partially deployed
          // server from advancing the finance cursor or clearing pending rows.
          'finance_acknowledged_changes': data['finance_acknowledged_changes'],
          'finance_conflicts': data['finance_conflicts'] ?? [],
          'finance_full_sync_required':
              data['finance_full_sync_required'] == true,
          'sync_capabilities': data['sync_capabilities'],
          'joined_team_uuids': data['joined_team_uuids'],
          'independent_completions':
              data['independent_completions'], // 🚀 独立完成状态
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

  /// 🚀 Uni-Sync 4.0: 标记一个远端项为忽略，防止其再次被拉回
  static Future<bool> ignoreRemoteItem({
    required String uuid,
    required String table,
    String? teamUuid,
  }) async {
    try {
      final response = await _request(
        'POST',
        '/api/sync/ignore_remote_item',
        body: {
          'uuid': uuid,
          'table_name': table,
          'team_uuid': teamUuid,
        },
      );
      return response.statusCode == 200;
    } catch (e) {
//       debugPrint("🚫 [ApiService] 忽略上报失败: $e");
      return false;
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
      final response = await _request(
        'POST',
        '/api/screen_time',
        body: {
          'user_id': userId,
          'device_name': deviceName,
          'record_date': date,
          'apps': apps,
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> fetchScreenTime(
    int userId,
    String date, {
    bool throwOnError = false,
  }) async {
    try {
      final response = await _request(
        'GET',
        '/api/screen_time?user_id=$userId&date=$date',
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      if (throwOnError) {
        throw StateError('screen_time HTTP ${response.statusCode}');
      }
      return [];
    } catch (e) {
      if (throwOnError) rethrow;
      return [];
    }
  }

  // ==========================================
  // 5. 调试工具 (Debug Tools)
  // ==========================================

  static Future<Map<String, dynamic>> debugResetDatabase() async {
    try {
      final response = await _request('POST', '/api/debug/reset_database');
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
      final response = await _request(
        'GET',
        '/api/mappings',
        includeAuth: false,
      );
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
      {String? semester}) async {
    try {
      final uri = semester != null
          ? Uri.parse(
              '$_effectiveBaseUrl/api/courses?user_id=$userId&semester=$semester')
          : Uri.parse('$_effectiveBaseUrl/api/courses?user_id=$userId');
      final response = await _request('GET', uri.toString());
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
      final response = await _request(
        'POST',
        '/api/courses',
        body: {
          'user_id': userId,
          'semester': semester,
          'courses': courses,
        },
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
    List<Map<String, dynamic>>? semesters, // 新增：多学期列表
  }) async {
    try {
      final body = <String, dynamic>{
        'semester_start': semesterStartMs,
        'semester_end': semesterEndMs,
      };
      if (semesters != null) {
        body['semesters'] = semesters;
      }
      final response = await _request('POST', '/api/settings', body: body);
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
      final response = await _request('GET', '/api/settings');
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取账户状态及注册时间。
  static Future<Map<String, dynamic>?> fetchUserStatus(int userId) async {
    try {
      final response = await _request(
        'GET',
        '/api/user/status?user_id=$userId',
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
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
      final response = await _request('GET', '/api/pomodoro/tags$urlPostfix');
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchTodos(int userId) async {
    try {
      final response = await _request('GET', '/api/todos?user_id=$userId');
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchCountdowns(int userId) async {
    try {
      final response = await _request('GET', '/api/countdowns?user_id=$userId');
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchTimeLogs(int userId) async {
    try {
      final response = await _request('GET', '/api/time_logs?user_id=$userId');
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 上传/同步标签到云端（Delta Sync）
  static Future<bool> syncPomodoroTags(List<Map<String, dynamic>> tags) async {
    try {
      final response = await _request(
        'POST',
        '/api/pomodoro/tags',
        body: {'tags': tags},
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      final conflicts = data is Map ? data['conflicts'] : null;
      return conflicts is! List || conflicts.isEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 上传单条专注记录（对齐 pomodoro_records 表）
  static Future<bool> uploadPomodoroRecord(Map<String, dynamic> record) async {
    try {
      final response = await _request(
        'POST',
        '/api/pomodoro/records',
        body: {'record': record},
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      final conflicts = data is Map ? data['conflicts'] : null;
      return conflicts is! List || conflicts.isEmpty;
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
    final response = await _request(
      'POST',
      '/api/migrate_register',
      body: {
        'email': email,
        'username': username,
        'password': password,
        'tier': tier,
        'semester_start': semesterStart,
        'semester_end': semesterEnd
      },
      includeAuth: false,
    );
    return jsonDecode(response.body);
  }

  /// 批量上传专注记录
  static Future<bool> uploadPomodoroRecords(
      List<Map<String, dynamic>> records) async {
    try {
      final response = await _request(
        'POST',
        '/api/pomodoro/records',
        body: {'records': records},
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      final conflicts = data is Map ? data['conflicts'] : null;
      return conflicts is! List || conflicts.isEmpty;
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
      final response = await _request('GET', uri.toString());
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
      final response = await _request(
        'POST',
        '/api/pomodoro/settings',
        body: settings,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 拉取番茄钟设置
  static Future<Map<String, dynamic>?> fetchPomodoroSettings() async {
    try {
      final response = await _request('GET', '/api/pomodoro/settings');
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
      final uri = Uri.parse('$_effectiveBaseUrl/api/pomodoro/active')
          .replace(queryParameters: {'device_id': currentDeviceId});
      final response = await _request('GET', uri.toString());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['active'] == true) {
          return data['record'] as Map<String, dynamic>?;
        }
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
      final response = await _request(
        'GET',
        '/api/online_stats',
        timeout: const Duration(seconds: 5),
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
      final response = await _request(
        'GET',
        '/api/device_version_stats',
        timeout: const Duration(seconds: 5),
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
      final response = await _request('GET', '/api/teams');
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
      final response =
          await _request('POST', '/api/teams/create', body: {'name': name});
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> generateInviteCode(
      String teamUuid) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/invite',
        body: {'team_uuid': teamUuid},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> addTeamMemberByEmail(
      String teamUuid, String email) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/members/add',
        body: {'team_uuid': teamUuid, 'email': email},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> joinTeamByCode(String code) async {
    try {
      final response =
          await _request('POST', '/api/teams/join', body: {'code': code});
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteTeam(String teamUuid) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/delete',
        body: {'team_uuid': teamUuid},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> selfCompleteTodo(String todoUuid) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/self_complete_todo',
        body: {'todo_uuid': todoUuid},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> selfResetTodo(String todoUuid) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/self_reset_todo',
        body: {'todo_uuid': todoUuid},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getTodoStatus(String todoUuid) async {
    try {
      final response = await _request(
        'GET',
        '/api/teams/todo_status?todo_uuid=$todoUuid',
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> leaveTeam(String teamUuid) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/leave',
        body: {'team_uuid': teamUuid},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<dynamic>> fetchTeamMembers(String teamUuid) async {
    try {
      final response = await _request(
        'GET',
        '/api/teams/members?team_uuid=$teamUuid',
      );
      final data = jsonDecode(response.body);
      return data['members'] ?? [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> removeTeamMember(
      String teamUuid, int targetUserId) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/members/remove',
        body: {'team_uuid': teamUuid, 'target_user_id': targetUserId},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- Uni-Sync V4.0 审批流接口 ---

  static Future<Map<String, dynamic>> getPoWChallenge() async {
    try {
      final response = await _request('GET', '/api/auth/pow_challenge');
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static String? _calculatePoW(String challenge, int difficulty) {
    String prefix = '0' * difficulty;
    int nonce = 0;
    while (true) {
      String content = challenge + nonce.toString();
      String hash = sha256.convert(utf8.encode(content)).toString();
      if (hash.startsWith(prefix)) return nonce.toString();
      nonce++;
      if (nonce > 1000000) return null; // 安全限制，防止死循环
    }
  }

  static Future<Map<String, dynamic>> requestJoinTeam(String code,
      {String message = ''}) async {
    try {
      final normalizedCode = code.trim().toUpperCase();
      if (normalizedCode.isEmpty) {
        return {'success': false, 'error': '邀请码不能为空'};
      }

      // 1. 获取挑战
      final challengeRes = await getPoWChallenge();
      if (challengeRes['success'] != true) return challengeRes;

      final challenge = challengeRes['challenge'];
      final difficulty = challengeRes['difficulty'] ?? 4;

      // 2. 计算 PoW
      final nonce = _calculatePoW(challenge, difficulty);
      if (nonce == null) return {'success': false, 'error': '算力验证失败'};

      // 3. 提交申请
      final response = await _request(
        'POST',
        '/api/teams/request_join',
        body: {
          'invite_code': normalizedCode,
          'message': message,
          'pow_challenge': challenge,
          'pow_nonce': nonce,
        },
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<dynamic>> fetchPendingRequests(String teamUuid) async {
    try {
      final response = await _request(
        'GET',
        '/api/teams/pending_requests?team_uuid=$teamUuid',
      );
      final data = jsonDecode(response.body);
      return data['requests'] ?? [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> processJoinRequest(
      String teamUuid, int targetUserId, String action) async {
    try {
      const allowedActions = {'approve', 'reject'};
      if (!allowedActions.contains(action)) {
        return {'success': false, 'error': '无效操作: $action'};
      }

      final response = await _request(
        'POST',
        '/api/teams/process_request',
        body: {
          'team_uuid': teamUuid,
          'target_user_id': targetUserId,
          'action': action
        },
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<dynamic>> fetchMyInvitations() async {
    try {
      final response = await _request('GET', '/api/teams/invitations');
      final data = jsonDecode(response.body);
      return data['invitations'] ?? [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> respondToInvitation(
      String teamUuid, String action) async {
    try {
      const allowedActions = {'accept', 'decline'};
      if (!allowedActions.contains(action)) {
        return {'success': false, 'error': '无效操作: $action'};
      }

      final response = await _request(
        'POST',
        '/api/teams/respond_invitation',
        body: {
          'team_uuid': teamUuid,
          'action': action,
        },
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 🚀 Uni-Sync 4.0: 获取团队系统消息流
  static Future<Map<String, dynamic>> fetchTeamSystemMessages(
      String teamUuid) async {
    try {
      final response = await _request(
        'GET',
        '/api/teams/system_messages?team_uuid=$teamUuid',
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==========================================
  // 🚀 10b. 团队公告 (Announcements)
  // ==========================================

  static Future<Map<String, dynamic>> createTeamAnnouncement(
      String teamUuid, String title, String content,
      {bool isPriority = false, int? expiresAt}) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/announcements/create',
        body: {
          'team_uuid': teamUuid,
          'title': title,
          'content': content,
          'is_priority': isPriority ? 1 : 0,
          'expires_at': expiresAt,
        },
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteTeamAnnouncement(
      String announcementUuid) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/announcements/delete',
        body: {'announcement_uuid': announcementUuid},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<dynamic>> fetchTeamAnnouncements(String teamUuid) async {
    try {
      final response = await _request(
        'GET',
        '/api/teams/announcements?team_uuid=$teamUuid',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['announcements'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> markAnnouncementAsRead(
      String announcementUuid) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/announcements/read',
        body: {'announcement_uuid': announcementUuid},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> fetchAnnouncementStats(
      String announcementUuid) async {
    try {
      final response = await _request(
        'GET',
        '/api/teams/announcements/stats?announcement_uuid=$announcementUuid',
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<dynamic>> fetchUnreadPriorityAnnouncements() async {
    try {
      final response = await _request(
        'GET',
        '/api/teams/announcements/unread_priority',
      );
      final data = jsonDecode(response.body);
      return data['announcements'] ?? [];
    } catch (e) {
      return [];
    }
  }

  // ==========================================
  // 🔗 10.5 团队分享 (Team Shares)
  // ==========================================

  static Future<Map<String, dynamic>> createTeamShare({
    required String teamUuid,
    String? title,
    String? description,
    bool shareTodos = true,
    bool shareSchedules = true,
    bool shareCountdowns = true,
    bool shareAnnouncements = true,
    String? password,
    int? expiresHours,
  }) async {
    try {
      final body = <String, dynamic>{
        'team_uuid': teamUuid,
        'share_todos': shareTodos,
        'share_schedules': shareSchedules,
        'share_countdowns': shareCountdowns,
        'share_announcements': shareAnnouncements,
      };
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (password != null && password.isNotEmpty) body['password'] = password;
      if (expiresHours != null) body['expires_hours'] = expiresHours;

      final response = await _request(
        'POST',
        '/api/teams/shares/create',
        body: body,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<dynamic>> fetchTeamShares(String teamUuid) async {
    try {
      final response = await _request(
        'GET',
        '/api/teams/shares?team_uuid=$teamUuid',
      );
      final data = jsonDecode(response.body);
      return data['shares'] ?? [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> deleteTeamShare(String shareCode) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/shares/delete',
        body: {'share_code': shareCode},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> updateTeamShare({
    required String shareCode,
    required bool isActive,
  }) async {
    try {
      final response = await _request(
        'POST',
        '/api/teams/shares/update',
        body: {
          'share_code': shareCode,
          'is_active': isActive,
        },
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> verifyShareCode(
      String code, String? password) async {
    try {
      final body = <String, dynamic>{};
      if (password != null && password.isNotEmpty) body['password'] = password;

      final response = await _request(
        'POST',
        '/api/shares/$code/verify',
        body: body,
        includeAuth: false,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> fetchShareData(String code,
      {String? token}) async {
    try {
      var url = '$_effectiveBaseUrl/api/shares/$code/data';
      if (token != null && token.isNotEmpty) {
        url += '?token=${Uri.encodeComponent(token)}';
      }
      final response = await _request(
        'GET',
        url,
        includeAuth: false,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> requestJoinViaShare({
    required String shareCode,
    required String email,
    String? message,
  }) async {
    try {
      final response = await _request(
        'POST',
        '/api/shares/$shareCode/request_join',
        body: {
          'email': email,
          if (message != null && message.isNotEmpty) 'message': message,
        },
        includeAuth: false,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==========================================
  // 🚀 11. 版本记录与回滚 (History & Rollback)
  // ==========================================

  static Future<List<dynamic>> fetchItemHistory(
      String uuid, String table) async {
    List<dynamic> combinedHistory = [];

    // 1. 尝试获取云端历史
    try {
      final response = await _request(
        'GET',
        '/api/sync/history?uuid=$uuid&table=$table',
        timeout: const Duration(seconds: 3),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        combinedHistory.addAll(data['history'] ?? []);
      } else if (response.statusCode == 403 || response.statusCode == 404) {
        // 后端权限收紧后，这两种状态是业务态，不当作网络异常
//         debugPrint("🔒 云端历史访问受限(status=${response.statusCode})，继续展示本地历史");
      } else {
//         debugPrint("⚠️ 云端历史接口异常(status=${response.statusCode})");
      }
    } catch (e) {
//       debugPrint("🌐 云端历史不可用，切换至纯本地模式: $e");
    }

    // 2. 获取本地历史并合并
    try {
      final localLogs =
          await DatabaseHelper.instance.getLocalAuditLogs(uuid, table);
      for (var log in localLogs) {
        // 转换本地格式为 UI 统一格式
        combinedHistory.add({
          'id': log['id'], // 注意：本地 ID 可能是 int
          'is_local': true, // 标记为本地记录
          'op_type': log['op_type'],
          'before_data': log['before_data'] != null
              ? jsonDecode(log['before_data'])
              : null,
          'after_data':
              log['after_data'] != null ? jsonDecode(log['after_data']) : null,
          'timestamp': log['timestamp'],
          'operator_name': log['operator_name'] ?? '本地修改',
        });
      }
    } catch (e) {
//       debugPrint("⚠️ 获取本地历史失败: $e");
    }

    // 3. 排序：按时间倒序
    combinedHistory.sort(
        (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    return combinedHistory;
  }

  static Future<Map<String, dynamic>> rollbackItem(dynamic logId,
      {bool isLocal = false, String? table, String? username}) async {
    // 🚀 如果是本地记录或处于离线状态，执行本地强力回滚（含缓存刷新）
    if (isLocal) {
      if (table == null || username == null) {
        return {'success': false, 'error': '缺少回滚上下文'};
      }
      final success =
          await StorageService.rollbackLocalItem(table, logId as int, username);
      return {'success': success, 'message': success ? '本地回滚成功' : '本地回滚失败'};
    }

    try {
      final response = await _request(
        'POST',
        '/api/sync/rollback',
        body: {'log_id': logId},
      );

      final Map<String, dynamic> data = jsonDecode(response.body);
      if (response.statusCode == 403 || response.statusCode == 404) {
        return {
          'success': false,
          'error': data['error'] ?? '无权限或记录不存在，无法回滚',
        };
      }
      return data;
    } catch (e) {
      return {'success': false, 'error': "网络错误，无法执行云端回滚"};
    }
  }

  /// Resolve a conflict on the server: clear the has_conflict flag.
  static Future<Map<String, dynamic>> resolveConflict({
    required String uuid,
    required String table,
    required String resolution, // 'keep_local' or 'accept_server'
    int? bumpedVersion,
    Map<String, dynamic>? data,
  }) async {
    try {
      final body = <String, dynamic>{
        'uuid': uuid,
        'table': table,
        'resolution': resolution,
      };
      if (bumpedVersion != null) body['version'] = bumpedVersion;
      if (data != null) body['data'] = data;

      final response = await _request(
        'POST',
        '/api/sync/resolve_conflict',
        body: body,
        timeout: const Duration(seconds: 5),
      );

      final result = jsonDecode(response.body);
      if (response.statusCode == 200 && result['success'] == true) {
        return {'success': true};
      }
      return {'success': false, 'error': result['error'] ?? '请求失败'};
    } catch (e) {
      return {'success': false, 'error': "网络错误: $e"};
    }
  }

  static Future<bool> markNotificationsRead(List<int> ids) async {
    if (ids.isEmpty) return true;
    try {
      final response = await _request(
        'POST',
        '/api/notifications/mark_read',
        body: {'ids': ids},
        timeout: const Duration(seconds: 5),
      );
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
