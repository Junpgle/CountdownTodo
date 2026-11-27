import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'database_helper.dart';
import 'http_client_factory.dart';
import '../storage_service.dart';
import '../utils/async_json.dart';
import '../utils/sync_error_formatter.dart';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

part 'api_service_sync.dart';
part 'api_service_team.dart';

class ApiService {
  static final RegExp _trailingSlashPattern = RegExp(r'/$');

  /// Persisted values for the production API route selector.
  ///
  /// Keep these values stable because older releases store them in
  /// SharedPreferences.
  static const String serverChoiceAliyunDirect = 'aliyun';
  static const String serverChoiceCloudflare = 'cloudflare';

  /// Current Aliyun production API endpoints.
  static const String aliyunCloudflareUrl = 'https://api-cdt.junpgle.me';
  static const String aliyunProdUrl = 'http://101.200.13.100:8082';
  static const String aliyunTestUrl = 'http://101.200.13.100:8084';

  /// The retired Cloudflare Worker is kept only for the historical migration
  /// flow. It must not be selected as the current app API endpoint.
  static const String legacyCloudflareUrl = 'https://mathquiz.junpgle.me';

  /// Backwards-compatible name used by the legacy migration code and tests.
  static const String cloudflareUrl = legacyCloudflareUrl;

  /// Web must use the HTTPS Zero Trust route because browsers cannot safely
  /// call the HTTP origin from an HTTPS page.
  static const String webAliyunProxyUrl = aliyunCloudflareUrl;

  /// Date after which an unreachable Cloudflare proxy route automatically falls
  /// back to the direct Aliyun HTTP endpoint on native platforms.
  static final DateTime cloudflareFallbackStartDate = DateTime(2027, 1, 16);

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  // Web must never start against the retired Cloudflare Worker. Share pages
  // intentionally skip the normal app initialization sequence, so the
  // default must already be the current API proxy before the first request.
  static String baseUrl = kIsWeb ? aliyunCloudflareUrl : aliyunProdUrl;
  static String? _baseUrlOverride;
  static bool _cloudflareFallbackActive = false;

  // 复用使用平台默认 TLS 证书校验的 HTTP 客户端。
  static http.Client? _clientInstance;
  static http.Client? _deltaSyncClient;
  static http.Client get _client {
    _clientInstance ??= createApiHttpClient();
    return _clientInstance!;
  }

  // 🛡️ 内存中持有最新 Token
  static String? _authToken;
  static String? _deviceId;
  static Future<void> Function(String reason)? onSessionRevoked;

  static void setToken(String token) {
    _authToken = token;
  }

  static void setDeviceId(String? deviceId) {
    _deviceId = deviceId?.trim();
  }

  static int currentUserId = 0;

  /// Atomically switches the in-memory identity used by authenticated syncs.
  static void setSession({required String token, required int userId}) {
    _authToken = token;
    currentUserId = userId;
  }

  // 🚀 公开获取 token 的方法（供 WebSocket 等服务使用）
  static String? getToken() => _authToken;

  static bool _isLocked = false;

  // 🚀 强制锁定环境地址（在 EnvironmentService 中调用）
  static void lockBaseUrl(String url) {
    baseUrl = url;
    _isLocked = true;
    _cloudflareFallbackActive = false;
  }

  static String normalizeServerChoice(String? choice) {
    return choice == serverChoiceCloudflare
        ? serverChoiceCloudflare
        : serverChoiceAliyunDirect;
  }

  // 初始化设置
  static void setServerChoice(String choice) {
    if (_isLocked) return; // 🛡️ 如果环境已锁定（如测试版），禁止通过设置更改地址

    _cloudflareFallbackActive = false;
    if (kIsWeb) {
      baseUrl = aliyunCloudflareUrl;
      return;
    }

    baseUrl = normalizeServerChoice(choice) == serverChoiceCloudflare
        ? aliyunCloudflareUrl
        : aliyunProdUrl;
  }

  // --- Migration Tool Support ---
  static void setBaseUrlOverride(String url) {
    _baseUrlOverride = url;
  }

  static void clearBaseUrlOverride() {
    _baseUrlOverride = null;
  }

  static bool get isCloudflareFallbackActive => _cloudflareFallbackActive;

  @visibleForTesting
  static void resetCloudflareFallbackForTest() {
    _cloudflareFallbackActive = false;
    clock = DateTime.now;
  }

  // Web 分享页必须始终走当前 Alibaba Zero Trust 代理。环境初始化、旧版
  // 本地设置或迁移工具都不应把浏览器请求重新指向已弃用的 Worker。
  static String get _effectiveBaseUrl {
    if (kIsWeb) return webAliyunProxyUrl;
    if (_baseUrlOverride != null) return _baseUrlOverride!;
    if (_cloudflareFallbackActive &&
        !_isLocked &&
        baseUrl == aliyunCloudflareUrl) {
      return aliyunProdUrl;
    }
    return baseUrl;
  }

  static String get effectiveBaseUrl => _effectiveBaseUrl;

  /// Stable namespace for sync watermarks. The current direct and Cloudflare
  /// routes share the Aliyun production namespace; test, legacy, and custom
  /// endpoints remain isolated.
  static String get syncServerKey {
    final normalized = _effectiveBaseUrl.replaceFirst(
      _trailingSlashPattern,
      '',
    );
    // Direct HTTP and Cloudflare HTTPS both reach the same Aliyun production
    // database, so switching routes must not create a second sync cursor.
    if (normalized == aliyunProdUrl || normalized == aliyunCloudflareUrl) {
      return 'aliyun';
    }
    if (normalized == aliyunTestUrl) return 'aliyun_test';
    if (normalized == legacyCloudflareUrl) return 'cf';
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
      if (includeAuth && _deviceId != null && _deviceId!.isNotEmpty)
        'X-Device-Id': _deviceId!,
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
    bool offloadBodyEncode = false,
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
        : offloadBodyEncode
        ? await encodeJsonOffload(
            body,
            estimatedItemCount: kAsyncJsonEncodeOffloadMinItems,
          )
        : jsonEncode(body);

    final requestClient = client ?? _client;
    http.Response response;
    try {
      response = await _sendHttpRequest(
        client: requestClient,
        method: method,
        uri: uri,
        headers: requestHeaders,
        body: encodedBody,
        timeout: timeout,
      );
      if (response.statusCode == 530) {
        final fallbackUri = _tryBuildCloudflareFallbackUri(uri);
        if (fallbackUri != null) {
          response = await _sendHttpRequest(
            client: requestClient,
            method: method,
            uri: fallbackUri,
            headers: requestHeaders,
            body: encodedBody,
            timeout: timeout,
          );
          _activateCloudflareFallback();
        }
      }
    } catch (e) {
      if (e is ArgumentError) rethrow;
      final fallbackUri = _tryBuildCloudflareFallbackUri(uri);
      if (fallbackUri == null) rethrow;
      response = await _sendHttpRequest(
        client: requestClient,
        method: method,
        uri: fallbackUri,
        headers: requestHeaders,
        body: encodedBody,
        timeout: timeout,
      );
      _activateCloudflareFallback();
    }

    if (includeAuth &&
        response.statusCode == 401 &&
        response.body.contains('SESSION_REVOKED')) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['code'] == 'SESSION_REVOKED') {
          final callback = onSessionRevoked;
          if (callback != null) {
            Future.microtask(() => callback('SESSION_REVOKED'));
          }
        }
      } catch (_) {}
    }

    return response;
  }

  static Future<http.Response> _sendHttpRequest({
    required http.Client client,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String? body,
    required Duration? timeout,
  }) async {
    late Future<http.Response> responseFuture;
    switch (method.toUpperCase()) {
      case 'GET':
        responseFuture = client.get(uri, headers: headers);
      case 'POST':
        responseFuture = client.post(uri, headers: headers, body: body);
      case 'PUT':
        responseFuture = client.put(uri, headers: headers, body: body);
      case 'DELETE':
        responseFuture = client.delete(uri, headers: headers, body: body);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
    return timeout == null
        ? await responseFuture
        : await responseFuture.timeout(timeout);
  }

  static Uri? _tryBuildCloudflareFallbackUri(Uri uri) {
    if (kIsWeb || _isLocked || _baseUrlOverride != null) return null;
    if (baseUrl != aliyunCloudflareUrl || _cloudflareFallbackActive) {
      return null;
    }
    if (clock().isBefore(cloudflareFallbackStartDate)) return null;

    final cfUri = Uri.parse(aliyunCloudflareUrl);
    if (uri.scheme != cfUri.scheme ||
        uri.host != cfUri.host ||
        uri.port != cfUri.port) {
      return null;
    }

    final directUri = Uri.parse(aliyunProdUrl);
    return uri.replace(
      scheme: directUri.scheme,
      host: directUri.host,
      port: directUri.port,
    );
  }

  static void _activateCloudflareFallback() {
    if (_cloudflareFallbackActive) return;
    _cloudflareFallbackActive = true;
    debugPrint(
      '⚠️ [ApiService] Cloudflare 代理不可达，已自动回退到阿里云直连: $aliyunProdUrl',
    );
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
    String username,
    String email,
    String password, {
    String? code,
    String? turnstileToken,
  }) async {
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

  static Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String? turnstileToken,
  }) async {
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
    String email,
    String code,
    String newPassword,
  ) async {
    try {
      final response = await _request(
        'POST',
        '/api/auth/reset_password',
        body: {'email': email, 'code': code, 'new_password': newPassword},
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
    int userId,
    String oldPassword,
    String newPassword,
  ) async {
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
        'message': data['message'] ?? data['error'] ?? '修改失败',
      };
    } catch (e) {
      return {'success': false, 'message': "网络错误: $e"};
    }
  }

  static Future<void> registerCurrentDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String appVersion,
  }) async {
    if (_authToken == null || _authToken!.isEmpty) return;
    try {
      await _request(
        'POST',
        '/api/auth/devices/register',
        body: {
          'device_id': deviceId,
          'device_name': deviceName,
          'platform': platform,
          'app_version': appVersion,
        },
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> fetchLoginDevices() async {
    try {
      final response = await _request(
        'GET',
        '/api/auth/devices',
        timeout: const Duration(seconds: 10),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'masked_email': data['masked_email'] ?? '',
          'devices': List<Map<String, dynamic>>.from(
            (data['devices'] as List? ?? const []).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          ),
        };
      }
      return {'success': false, 'message': data['error'] ?? '获取登录设备失败'};
    } catch (e) {
      return {'success': false, 'message': '网络错误: $e'};
    }
  }

  static Future<Map<String, dynamic>> sendKickDeviceCode(
    String deviceId,
  ) async {
    try {
      final response = await _request(
        'POST',
        '/api/auth/devices/send_kick_code',
        body: {'device_id': deviceId},
        timeout: const Duration(seconds: 12),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message'] ?? data['error'] ?? '发送验证码失败',
        'masked_email': data['masked_email'],
      };
    } catch (e) {
      return {'success': false, 'message': '网络错误: $e'};
    }
  }

  static Future<Map<String, dynamic>> kickDevice(
    String deviceId,
    String code,
  ) async {
    try {
      final response = await _request(
        'POST',
        '/api/auth/devices/kick',
        body: {'device_id': deviceId, 'code': code},
        timeout: const Duration(seconds: 12),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message'] ?? data['error'] ?? '踢出设备失败',
      };
    } catch (e) {
      return {'success': false, 'message': '网络错误: $e'};
    }
  }

  static Future<void> logoutCurrentDevice() async {
    if (_authToken == null || _authToken!.isEmpty) return;
    try {
      await _request(
        'POST',
        '/api/auth/logout',
        body: {if (_deviceId != null) 'device_id': _deviceId},
        timeout: const Duration(seconds: 4),
      );
    } catch (_) {}
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

  static Future<bool> uploadScore({
    required int userId,
    required String username,
    required int score,
    required int duration,
  }) async {
    try {
      final response = await _request(
        'POST',
        '/api/score',
        body: {
          'user_id': userId,
          'username': username,
          'score': score,
          'duration': duration,
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
    List<Map<String, dynamic>> habitDrinkOptionChanges = const [],
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
  }) => _apiSyncPostDeltaSync(
    userId: userId,
    lastSyncTime: lastSyncTime,
    deviceId: deviceId,
    todosChanges: todosChanges,
    countdownsChanges: countdownsChanges,
    todoGroupsChanges: todoGroupsChanges,
    screenTime: screenTime,
    forceFullSync: forceFullSync,
    timeLogsChanges: timeLogsChanges,
    planBlocksChanges: planBlocksChanges,
    fixedSchedulesChanges: fixedSchedulesChanges,
    fixedSchedulesFullSync: fixedSchedulesFullSync,
    pomodoroChanges: pomodoroChanges,
    tagChanges: tagChanges,
    habitGoalsChanges: habitGoalsChanges,
    habitRuleChanges: habitRuleChanges,
    habitCheckInChanges: habitCheckInChanges,
    habitSleepCoachingPlanChanges: habitSleepCoachingPlanChanges,
    habitDrinkOptionChanges: habitDrinkOptionChanges,
    habitFullSync: habitFullSync,
    habitLastSyncTime: habitLastSyncTime,
    syncHabits: syncHabits,
    financeCategoryChanges: financeCategoryChanges,
    financePaymentMethodChanges: financePaymentMethodChanges,
    financeTransactionChanges: financeTransactionChanges,
    financeLoanChanges: financeLoanChanges,
    financeLoanInstallmentChanges: financeLoanInstallmentChanges,
    financeBudgetChanges: financeBudgetChanges,
    financeRecurringRuleChanges: financeRecurringRuleChanges,
    financeTemplateChanges: financeTemplateChanges,
    financeFullSync: financeFullSync,
    financeLastSyncTime: financeLastSyncTime,
    syncFinance: syncFinance,
  );

  /// 🚀 Uni-Sync 4.0: 标记一个远端项为忽略，防止其再次被拉回
  static Future<bool> ignoreRemoteItem({
    required String uuid,
    required String table,
    String? teamUuid,
  }) => _apiSyncIgnoreRemoteItem(uuid: uuid, table: table, teamUuid: teamUuid);

  static Future<bool> uploadScreenTime({
    required int userId,
    required String deviceName,
    required String date,
    required List<Map<String, dynamic>> apps,
  }) => _apiSyncUploadScreenTime(
    userId: userId,
    deviceName: deviceName,
    date: date,
    apps: apps,
  );

  static Future<List<dynamic>> fetchScreenTime(
    int userId,
    String date, {
    bool throwOnError = false,
  }) => _apiSyncFetchScreenTime(userId, date, throwOnError: throwOnError);

  static Future<Map<String, dynamic>> debugResetDatabase() =>
      _apiSyncDebugResetDatabase();

  static Future<List<dynamic>?> fetchAppMappings() =>
      _apiSyncFetchAppMappings();

  static Future<List<dynamic>> fetchCourses(int userId, {String? semester}) =>
      _apiSyncFetchCourses(userId, semester: semester);

  /// Returns all courses known by the server, including configured semesters.
  ///
  /// New servers understand `semester=all`.  The per-semester requests remain
  /// as a compatibility path for older deployments and also cover servers
  /// that do not persist the semester list in user settings.
  static Future<List<dynamic>> fetchCoursesForSemesters(
    int userId,
    Iterable<String> semesterIds, {
    bool includeAll = true,
  }) => _apiSyncFetchCoursesForSemesters(
    userId,
    semesterIds,
    includeAll: includeAll,
  );

  static List<String> semesterIdsFromSettings(Map<String, dynamic>? settings) =>
      _apiSyncSemesterIdsFromSettings(settings);

  static Future<List<dynamic>> fetchAllCourses(int userId) =>
      _apiSyncFetchAllCourses(userId);

  /// The multi-semester course replacement must be performed by one server
  /// transaction.  Older servers only understand the per-semester endpoint,
  /// so callers must verify this capability before sending the new payload.
  static Future<bool> supportsAtomicCourseUpload() =>
      _apiSyncSupportsAtomicCourseUpload();

  static Future<Map<String, dynamic>> uploadCourses({
    required int userId,
    required List<Map<String, dynamic>> courses,
    String semester = "default",
    bool replaceAll = false,
    bool atomicAllSemesters = false,
  }) => _apiSyncUploadCourses(
    userId: userId,
    courses: courses,
    semester: semester,
    replaceAll: replaceAll,
    atomicAllSemesters: atomicAllSemesters,
  );

  /// 上传开学/放假时间到云端（毫秒时间戳，null 表示清除）
  static Future<bool> uploadUserSettings({
    required int? semesterStartMs,
    required int? semesterEndMs,
    List<Map<String, dynamic>>? semesters, // 新增：多学期列表
  }) => _apiSyncUploadUserSettings(
    semesterStartMs: semesterStartMs,
    semesterEndMs: semesterEndMs,
    semesters: semesters,
  );

  /// 从云端拉取开学/放假时间（返回毫秒时间戳，null 表示未设置）
  static Future<Map<String, dynamic>?> fetchUserSettings() =>
      _apiSyncFetchUserSettings();

  /// 获取账户状态及注册时间。
  static Future<Map<String, dynamic>?> fetchUserStatus(int userId) =>
      _apiSyncFetchUserStatus(userId);

  /// 拉取用户标签（含已删除，供 LWW 合并）
  static Future<List<dynamic>> fetchPomodoroTags([int? userId]) =>
      _apiSyncFetchPomodoroTags(userId);

  static Future<List<dynamic>> fetchTodos(int userId) =>
      _apiSyncFetchTodos(userId);

  static Future<List<dynamic>> fetchCountdowns(int userId) =>
      _apiSyncFetchCountdowns(userId);

  static Future<List<dynamic>> fetchTimeLogs(int userId) =>
      _apiSyncFetchTimeLogs(userId);

  /// 上传/同步标签到云端（Delta Sync）
  static Future<bool> syncPomodoroTags(List<Map<String, dynamic>> tags) =>
      _apiSyncSyncPomodoroTags(tags);

  /// 上传单条专注记录（对齐 pomodoro_records 表）
  static Future<bool> uploadPomodoroRecord(Map<String, dynamic> record) =>
      _apiSyncUploadPomodoroRecord(record);

  static Future<Map<String, dynamic>> migrationRegister({
    required String email,
    required String username,
    required String password,
    String tier = 'free',
    int? semesterStart,
    int? semesterEnd,
  }) => _apiSyncMigrationRegister(
    email: email,
    username: username,
    password: password,
    tier: tier,
    semesterStart: semesterStart,
    semesterEnd: semesterEnd,
  );

  /// 批量上传专注记录
  static Future<bool> uploadPomodoroRecords(
    List<Map<String, dynamic>> records, {
    http.Client? client,
  }) => _apiSyncUploadPomodoroRecords(records, client: client);

  /// 拉取专注记录（按时间范围）
  static Future<List<dynamic>> fetchPomodoroRecords([
    int? userId,
    int? fromMs,
    int? toMs,
    bool includeDeleted = false,
    bool useUpdatedAt = false,
    http.Client? client,
  ]) => _apiSyncFetchPomodoroRecords(
    userId,
    fromMs,
    toMs,
    includeDeleted,
    useUpdatedAt,
    client,
  );

  /// 同步番茄钟设置到云端
  static Future<bool> syncPomodoroSettings(Map<String, dynamic> settings) =>
      _apiSyncSyncPomodoroSettings(settings);

  /// 拉取番茄钟设置
  static Future<Map<String, dynamic>?> fetchPomodoroSettings() =>
      _apiSyncFetchPomodoroSettings();

  /// 查询其他设备是否有正在进行的专注（跨端感知）
  static Future<Map<String, dynamic>?> fetchActivePomodoroFromOtherDevice(
    String currentDeviceId,
  ) => _apiSyncFetchActivePomodoroFromOtherDevice(currentDeviceId);

  /// 获取当前在线设备分布统计
  static Future<Map<String, dynamic>?> fetchOnlineStats() =>
      _apiSyncFetchOnlineStats();

  /// 获取所有设备历史版本分布统计（含离线设备）
  static Future<Map<String, dynamic>?> fetchDeviceVersionStats() =>
      _apiSyncFetchDeviceVersionStats();

  /// 获取近7日全站番茄钟专注日均统计（若后端不支持或无数据则返回 null）
  static Future<Map<String, dynamic>?> fetchPomodoroCommunityStats({
    required int fromMs,
    required int toMs,
  }) => _apiSyncFetchPomodoroCommunityStats(fromMs: fromMs, toMs: toMs);

  // 向后兼容旧方法名
  static Future<bool> uploadPomodoroSessions(
    List<Map<String, dynamic>> sessions,
  ) => _apiSyncUploadPomodoroSessions(sessions);

  static Future<List<dynamic>> fetchPomodoroSessions({
    int? fromMs,
    int? toMs,
    bool includeDeleted = false,
    bool useUpdatedAt = false,
    http.Client? client,
  }) => _apiSyncFetchPomodoroSessions(
    fromMs: fromMs,
    toMs: toMs,
    includeDeleted: includeDeleted,
    useUpdatedAt: useUpdatedAt,
    client: client,
  );

  static Future<List<dynamic>> fetchTeams() => _apiTeamFetchTeams();

  /// Returns whether the teams request actually succeeded, even when the user
  /// has no teams. Search warmup uses this to avoid caching network failures as
  /// a valid empty result.
  static Future<({bool succeeded, List<dynamic> teams})> fetchTeamsWithStatus({
    http.Client? client,
  }) => _apiTeamFetchTeamsWithStatus(client: client);

  static Future<Map<String, dynamic>> createTeam(String name) =>
      _apiTeamCreateTeam(name);

  static Future<Map<String, dynamic>> generateInviteCode(String teamUuid) =>
      _apiTeamGenerateInviteCode(teamUuid);

  static Future<Map<String, dynamic>> addTeamMemberByEmail(
    String teamUuid,
    String email,
  ) => _apiTeamAddTeamMemberByEmail(teamUuid, email);

  static Future<Map<String, dynamic>> joinTeamByCode(String code) =>
      _apiTeamJoinTeamByCode(code);

  static Future<Map<String, dynamic>> deleteTeam(String teamUuid) =>
      _apiTeamDeleteTeam(teamUuid);

  static Future<Map<String, dynamic>> selfCompleteTodo(String todoUuid) =>
      _apiTeamSelfCompleteTodo(todoUuid);

  static Future<Map<String, dynamic>> selfResetTodo(String todoUuid) =>
      _apiTeamSelfResetTodo(todoUuid);

  static Future<Map<String, dynamic>> getTodoStatus(String todoUuid) =>
      _apiTeamGetTodoStatus(todoUuid);

  static Future<Map<String, dynamic>> leaveTeam(String teamUuid) =>
      _apiTeamLeaveTeam(teamUuid);

  static Future<List<dynamic>> fetchTeamMembers(String teamUuid) =>
      _apiTeamFetchTeamMembers(teamUuid);

  static Future<Map<String, dynamic>> removeTeamMember(
    String teamUuid,
    int targetUserId,
  ) => _apiTeamRemoveTeamMember(teamUuid, targetUserId);

  static Future<Map<String, dynamic>> getPoWChallenge() =>
      _apiTeamGetPoWChallenge();

  static Future<Map<String, dynamic>> requestJoinTeam(
    String code, {
    String message = '',
  }) => _apiTeamRequestJoinTeam(code, message: message);

  static Future<List<dynamic>> fetchPendingRequests(String teamUuid) =>
      _apiTeamFetchPendingRequests(teamUuid);

  static Future<Map<String, dynamic>> processJoinRequest(
    String teamUuid,
    int targetUserId,
    String action,
  ) => _apiTeamProcessJoinRequest(teamUuid, targetUserId, action);

  static Future<List<dynamic>> fetchMyInvitations() =>
      _apiTeamFetchMyInvitations();

  static Future<Map<String, dynamic>> respondToInvitation(
    String teamUuid,
    String action,
  ) => _apiTeamRespondToInvitation(teamUuid, action);

  /// 🚀 Uni-Sync 4.0: 获取团队系统消息流
  static Future<Map<String, dynamic>> fetchTeamSystemMessages(
    String teamUuid, {
    int? limit,
    int? offset,
  }) => _apiTeamFetchTeamSystemMessages(teamUuid, limit: limit, offset: offset);

  static Future<Map<String, dynamic>> createTeamAnnouncement(
    String teamUuid,
    String title,
    String content, {
    bool isPriority = false,
    int? expiresAt,
  }) => _apiTeamCreateTeamAnnouncement(
    teamUuid,
    title,
    content,
    isPriority: isPriority,
    expiresAt: expiresAt,
  );

  static Future<Map<String, dynamic>> deleteTeamAnnouncement(
    String announcementUuid, {
    String? teamUuid,
  }) => _apiTeamDeleteTeamAnnouncement(announcementUuid, teamUuid: teamUuid);

  static Future<List<dynamic>> fetchTeamAnnouncements(String teamUuid) =>
      _apiTeamFetchTeamAnnouncements(teamUuid);

  static Future<Map<String, dynamic>> markAnnouncementAsRead(
    String announcementUuid,
  ) => _apiTeamMarkAnnouncementAsRead(announcementUuid);

  static Future<Map<String, dynamic>> fetchAnnouncementStats(
    String announcementUuid,
  ) => _apiTeamFetchAnnouncementStats(announcementUuid);

  static Future<List<dynamic>> fetchUnreadPriorityAnnouncements() =>
      _apiTeamFetchUnreadPriorityAnnouncements();

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
  }) => _apiTeamCreateTeamShare(
    teamUuid: teamUuid,
    title: title,
    description: description,
    shareTodos: shareTodos,
    shareSchedules: shareSchedules,
    shareCountdowns: shareCountdowns,
    shareAnnouncements: shareAnnouncements,
    password: password,
    expiresHours: expiresHours,
  );

  static Future<List<dynamic>> fetchTeamShares(String teamUuid) =>
      _apiTeamFetchTeamShares(teamUuid);

  static Future<Map<String, dynamic>> deleteTeamShare(String shareCode) =>
      _apiTeamDeleteTeamShare(shareCode);

  static Future<Map<String, dynamic>> updateTeamShare({
    required String shareCode,
    required bool isActive,
  }) => _apiTeamUpdateTeamShare(shareCode: shareCode, isActive: isActive);

  static Future<Map<String, dynamic>> verifyShareCode(
    String code,
    String? password,
  ) => _apiTeamVerifyShareCode(code, password);

  static Future<Map<String, dynamic>> fetchShareData(
    String code, {
    String? token,
    bool includeHistory = false,
  }) => _apiTeamFetchShareData(
    code,
    token: token,
    includeHistory: includeHistory,
  );

  static Future<Map<String, dynamic>> requestJoinViaShare({
    required String shareCode,
    required String email,
    String? message,
    String? accessToken,
  }) => _apiTeamRequestJoinViaShare(
    shareCode: shareCode,
    email: email,
    message: message,
    accessToken: accessToken,
  );

  static Future<List<dynamic>> fetchItemHistory(String uuid, String table) =>
      _apiTeamFetchItemHistory(uuid, table);

  static Future<Map<String, dynamic>> rollbackItem(
    dynamic logId, {
    bool isLocal = false,
    String? table,
    String? username,
  }) => _apiTeamRollbackItem(
    logId,
    isLocal: isLocal,
    table: table,
    username: username,
  );

  /// Resolve a conflict on the server: clear the has_conflict flag.
  static Future<Map<String, dynamic>> resolveConflict({
    required String uuid,
    required String table,
    required String resolution, // 'keep_local' or 'accept_server'
    int? bumpedVersion,
    Map<String, dynamic>? data,
  }) => _apiTeamResolveConflict(
    uuid: uuid,
    table: table,
    resolution: resolution,
    bumpedVersion: bumpedVersion,
    data: data,
  );

  static Future<bool> markNotificationsRead(List<int> ids) =>
      _apiTeamMarkNotificationsRead(ids);
}
