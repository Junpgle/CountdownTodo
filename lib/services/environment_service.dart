import 'package:package_info_plus/package_info_plus.dart';
import '../storage_service.dart';
import 'api_service.dart';
import 'turnstile_site_key_resolver.dart';

/// 🚀 Uni-Sync 4.0: 环境与隔离管理服务
class EnvironmentService {
  static bool _isTest = false;
  static String _packageName = "";

  // ============================================================
  // 🔐 Cloudflare Turnstile 配置
  // ============================================================

  /// Turnstile Site Key（客户端使用）
  /// 测试环境：Cloudflare 官方测试 key（始终返回成功）
  /// 生产环境：通过 --dart-define=TURNSTILE_SITE_KEY=xxx 注入真实 key
  static const String _turnstileSiteKey = String.fromEnvironment(
    'TURNSTILE_SITE_KEY',
    defaultValue: '0x4AAAAAADkYYUiQdEWVhVYh', // 生产 key
  );

  /// 测试环境专用 key（仅 debug 包使用）
  static const String _testSiteKey = String.fromEnvironment(
    'TURNSTILE_TEST_SITE_KEY',
    defaultValue: '1x00000000000000000000AA', // Cloudflare 官方测试 key
  );

  /// 本地 Web 调试默认用测试 key 避免 localhost 触发 110200。
  /// 若已在 Turnstile Hostname Management 允许本地域名，可通过 dart-define
  /// TURNSTILE_USE_PRODUCTION_ON_LOCAL_WEB=true 强制使用生产 key。
  static const bool _useProductionTurnstileOnLocalWeb = bool.fromEnvironment(
    'TURNSTILE_USE_PRODUCTION_ON_LOCAL_WEB',
    defaultValue: false,
  );

  /// Turnstile 验证页面 URL（WebView 使用）
  /// 生产环境必须配置为后端地址，例如 https://api-cdt.junpgle.me/turnstile
  static const String _turnstileVerifyPageUrl = String.fromEnvironment(
    'TURNSTILE_VERIFY_PAGE_URL',
    defaultValue: '', // 默认使用当前后端地址 + /turnstile
  );

  /// 获取 Turnstile Site Key（根据环境自动选择）
  static String get turnstileSiteKey => resolveTurnstileSiteKey(
        isTest: _isTest,
        testSiteKey: _testSiteKey,
        productionSiteKey: _turnstileSiteKey,
        useProductionOnLocalWeb: _useProductionTurnstileOnLocalWeb,
      );

  /// 获取 Turnstile 验证页面完整 URL
  /// 必须是后端 Express 服务器的 /turnstile 路由，不是 Cloudflare Worker
  static String get turnstileVerifyPageUrl {
    // 优先使用显式配置
    if (_turnstileVerifyPageUrl.isNotEmpty) return _turnstileVerifyPageUrl;
    // 根据环境选择正确的后端地址（Express 服务器，不是 CF Worker）
    if (_isTest) return '${ApiService.aliyunTestUrl}/turnstile';
    // 生产环境：统一走 Cloudflare Zero Trust（HTTPS），避免原生平台 HTTP 被 ATS 拦截
    return 'https://api-cdt.junpgle.me/turnstile';
  }

  /// 启动时初始化
  static Future<void> init() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _packageName = packageInfo.packageName;

    // 🛡️ 自动探测：如果包名包含 .debug，强制判定为测试环境
    _isTest = _packageName.endsWith('.debug');

    if (_isTest) {
      // 🔌 测试环境：强制锁定到阿里云 8084 测试服务器
      ApiService.lockBaseUrl(ApiService.aliyunTestUrl);
    } else {
      // 🔌 生产环境：根据用户选择决定
      String serverChoice = await StorageService.getServerChoice();
      ApiService.setServerChoice(serverChoice);
//       print(
//           '🔌 [Environment] Mode: PROD (Current Base: ${ApiService.baseUrl})');
    }
  }

  /// 获取当前包名
  static String get packageName => _packageName;

  /// 是否为测试环境
  static bool get isTest => _isTest;

  /// 根据环境返回对应的数据库文件名
  static String get dbName =>
      _isTest ? 'uni_sync_test_v5.db' : 'uni_sync_v4.db';

  /// 环境标签名
  static String get envLabel => _isTest ? "测试版" : "正式版";
}
