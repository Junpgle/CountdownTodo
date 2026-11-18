import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../storage_service.dart';
import '../utils/navigator_utils.dart';
import '../utils/page_transitions.dart';
import 'api_service.dart';
import 'pomodoro_sync_service.dart';
import 'reminder_schedule_service.dart';

/// Handles forced logout when the current device session is revoked remotely.
class SessionRevocationService {
  SessionRevocationService._();

  static bool _isHandling = false;
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    ApiService.onSessionRevoked = (_) => handleSessionRevoked();
  }

  static Future<void> handleSessionRevoked({String? message}) async {
    if (_isHandling) return;
    final token = ApiService.getToken();
    if (token == null || token.isEmpty) return;

    _isHandling = true;
    try {
      PomodoroSyncService.instance.disconnect();
      await ReminderScheduleService.clearScheduledReminders().catchError(
        (_) {},
      );
      await StorageService.clearLoginSession();

      final navState = appNavigatorKey.currentState;
      final context = appNavigatorKey.currentContext;
      if (navState != null) {
        navState.pushAndRemoveUntil(
          PageTransitions.material(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }

      if (context != null && context.mounted) {
        final notice = message ?? '当前设备已被其他设备踢下线，请重新登录';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final currentContext = appNavigatorKey.currentContext;
          if (currentContext != null && currentContext.mounted) {
            ScaffoldMessenger.of(currentContext).showSnackBar(
              SnackBar(
                content: Text(notice),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
      }
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _isHandling = false;
      });
    }
  }
}
