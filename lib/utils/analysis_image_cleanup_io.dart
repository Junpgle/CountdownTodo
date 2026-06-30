import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Future<void> cleanupAnalysisImagesImpl() async {
  try {
    final appDir = await getApplicationSupportDirectory();
    final imageDir = Directory('${appDir.path}/analysis_images');
    if (!await imageDir.exists()) return;

    final now = DateTime.now();
    final expiration = now.subtract(const Duration(days: 7));
    final files = imageDir.listSync();
    var deletedCount = 0;

    for (final file in files) {
      if (file is File) {
        final stat = await file.stat();
        if (stat.modified.isBefore(expiration)) {
          await file.delete();
          deletedCount++;
        }
      }
    }
    if (deletedCount > 0) {
      debugPrint('🧹 清理了 $deletedCount 个过期的识别图片');
    }
  } catch (e) {
    debugPrint('❌ 清理识别图片失败: $e');
  }
}
