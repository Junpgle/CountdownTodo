import 'package:flutter/material.dart';

import '../features/finance/models/finance_models.dart';
import '../storage_service.dart';

class ExternalShareHandler {
  static void init(
    BuildContext context,
    Function onCourseImported, {
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
    Future<void> Function(List<FinanceEntryDraft>, String?)?
        onFinanceRecognized,
  }) {}

  static void dispose() {}

  static Future<Map<String, dynamic>?> getPendingTodoConfirm() {
    return StorageService.getPendingTodoConfirm();
  }

  static Future<void> clearPendingTodoConfirm() {
    return StorageService.clearPendingTodoConfirm();
  }

  static Future<void> clearPendingFinanceRecognized() async {
    final pending = await StorageService.getPendingTodoConfirm();
    if (pending == null) return;
    await StorageService.updatePendingTodoConfirmStatus(
      status: pending['status']?.toString() ?? 'success',
      financeResults: const [],
    );
  }

  static Future<void> retryTodoRecognition({
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
    Future<void> Function(List<FinanceEntryDraft>, String?)?
        onFinanceRecognized,
  }) async {
    await StorageService.updatePendingTodoConfirmStatus(
      status: 'failed',
      errorMsg: 'Web 端暂不支持从系统分享入口重试图片识别',
    );
    onTodoRecognized?.call(const <Map<String, dynamic>>[], null);
  }
}
