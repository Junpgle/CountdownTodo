import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../screens/personal_timeline_screen.dart';
import '../storage_service.dart';
import '../utils/navigator_utils.dart';
import '../utils/page_transitions.dart';

class AppDeepLinkService {
  static const String scheme = 'countdowntodo';
  static const MethodChannel _channel =
      MethodChannel('com.math_quiz_app/deep_links');
  static Uri? _pendingUri;
  static bool _initialized = false;

  static Future<void> init(List<String> launchArgs) async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openDeepLink') {
        final raw = call.arguments?.toString();
        if (raw != null && raw.isNotEmpty) {
          await handleUriString(raw);
        }
      }
    });

    for (final arg in launchArgs) {
      if (_looksLikeDeepLink(arg)) {
        unawaited(handleUriString(arg));
        break;
      }
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMethod<String>('getInitialDeepLink');
        if (raw != null && raw.isNotEmpty) {
          unawaited(handleUriString(raw));
        }
      } catch (_) {}
    }

    if (!kIsWeb && Platform.isWindows) {
      unawaited(_registerWindowsProtocol());
    }
  }

  static Future<void> handleUriString(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != scheme) return;
    _pendingUri = uri;
    await _tryConsumePending();
  }

  static Future<void> consumePendingAfterAppReady() => _tryConsumePending();

  static Future<void> _tryConsumePending({int attempt = 0}) async {
    final uri = _pendingUri;
    if (uri == null) return;

    final navigator = appNavigatorKey.currentState;
    final context = appNavigatorKey.currentContext;
    final username = await StorageService.getLoginSession();
    if (navigator == null ||
        context == null ||
        username == null ||
        username.isEmpty) {
      if (attempt < 30) {
        Future.delayed(
          const Duration(milliseconds: 300),
          () => _tryConsumePending(attempt: attempt + 1),
        );
      }
      return;
    }

    _pendingUri = null;
    final target = _TimelineReportTarget.fromUri(uri);
    if (target == null) return;

    navigator.push(
      PageTransitions.slideHorizontal(
        PersonalTimelineScreen(
          username: username,
          initialDimension: target.dimension,
          initialDate: target.date,
        ),
      ),
    );
  }

  static bool _looksLikeDeepLink(String value) {
    return value.startsWith('$scheme://') || value.startsWith('$scheme:/');
  }

  static Future<void> _registerWindowsProtocol() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final commands = [
        [
          'add',
          'HKCU\\Software\\Classes\\$scheme',
          '/ve',
          '/d',
          'URL:CountDownTodo',
          '/f'
        ],
        [
          'add',
          'HKCU\\Software\\Classes\\$scheme',
          '/v',
          'URL Protocol',
          '/d',
          '',
          '/f'
        ],
        [
          'add',
          'HKCU\\Software\\Classes\\$scheme\\DefaultIcon',
          '/ve',
          '/d',
          exePath,
          '/f'
        ],
        [
          'add',
          'HKCU\\Software\\Classes\\$scheme\\shell\\open\\command',
          '/ve',
          '/d',
          '"$exePath" "%1"',
          '/f'
        ],
      ];
      for (final args in commands) {
        await Process.run('reg', args);
      }
    } catch (e) {
      debugPrint('[DeepLink] Windows protocol registration failed: $e');
    }
  }
}

class _TimelineReportTarget {
  const _TimelineReportTarget({
    required this.dimension,
    required this.date,
  });

  final TimelineDimension dimension;
  final DateTime date;

  static _TimelineReportTarget? fromUri(Uri uri) {
    final isTimelineReport = uri.host == 'timeline' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'report';
    if (!isTimelineReport) return null;

    final dimension = _parseDimension(uri.queryParameters['dimension']);
    final date = _parseDate(uri.queryParameters['date']) ?? DateTime.now();
    return _TimelineReportTarget(dimension: dimension, date: date);
  }

  static TimelineDimension _parseDimension(String? value) {
    return TimelineDimension.values.firstWhere(
      (d) => d.name == value,
      orElse: () => TimelineDimension.daily,
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(value);
    } catch (_) {
      return null;
    }
  }
}
