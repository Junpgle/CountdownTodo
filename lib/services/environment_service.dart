import 'package:package_info_plus/package_info_plus.dart';
import '../storage_service.dart';
import 'api_service.dart';

/// 🚀 Uni-Sync 4.0: 环境与隔离管理服务
class EnvironmentService {
  static bool _isTest = false;
  static String _packageName = "";

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
      print('🔌 [Environment] Mode: PROD (Current Base: ${ApiService.baseUrl})');
    }
  }

  /// 获取当前包名
  static String get packageName => _packageName;

  /// 是否为测试环境
  static bool get isTest => _isTest;

  /// 根据环境返回对应的数据库文件名
  static String get dbName => _isTest ? 'uni_sync_test_v5.db' : 'uni_sync_v4.db';
  
  /// 环境标签名
  static String get envLabel => _isTest ? "测试版" : "正式版";
}
