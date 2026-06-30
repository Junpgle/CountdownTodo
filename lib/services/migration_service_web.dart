import 'package:flutter/material.dart';

class MigrationService {
  static Future<void> runMigration({
    required BuildContext context,
    required String oldUrl,
    required String newUrl,
    required String email,
    required String password,
    required Function(String) onProgress,
  }) async {
    onProgress('Web 端暂不支持旧服务器迁移工具，请在桌面或移动端执行。');
    throw UnsupportedError('Web 端暂不支持旧服务器迁移工具');
  }
}
