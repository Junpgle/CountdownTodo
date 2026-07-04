import 'package:flutter/material.dart';

import '../storage_service.dart';

class ExternalShareHandler {
  static void init(
    BuildContext context,
    Function onCourseImported, {
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
  }) {}

  static void dispose() {}

  static Future<Map<String, dynamic>?> getPendingTodoConfirm() {
    return StorageService.getPendingTodoConfirm();
  }

  static Future<void> clearPendingTodoConfirm() {
    return StorageService.clearPendingTodoConfirm();
  }

  static Future<void> retryTodoRecognition({
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
  }) async {
    await StorageService.updatePendingTodoConfirmStatus(
      status: 'failed',
      errorMsg: 'Web 端暂不支持从系统分享入口重试图片识别',
    );
    onTodoRecognized?.call(const <Map<String, dynamic>>[], null);
  }
}
