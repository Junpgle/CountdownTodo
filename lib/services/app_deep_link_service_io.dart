import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../features/habits/screens/habit_center_screen.dart';
import '../features/habits/services/habit_widget_checkin.dart';
import '../features/finance/screens/finance_home_screen.dart';
import '../screens/course_screens.dart';
import '../screens/personal_timeline_screen.dart';
import '../storage_service.dart';
import '../utils/navigator_utils.dart';
import '../utils/page_transitions.dart';
import '../utils/todo_recurrence_picker.dart';
import 'widget_service_io.dart';

class AppDeepLinkService {
  static const String scheme = 'countdowntodo';
  static const MethodChannel _channel =
      MethodChannel('com.math_quiz_app/deep_links');
  static Uri? _pendingUri;
  static bool _initialized = false;
  // Deep links can arrive while MyApp is still replacing its splash/checking
  // route with the authenticated home route. Hold them until that root route
  // has settled; otherwise the later MaterialApp rebuild can cover the page
  // opened from a widget.
  static bool _appReady = false;
  static bool _readingNativePending = false;
  static String? _lastHandledRaw;
  static DateTime? _lastHandledAt;
  static final _lifecycleObserver = _AppDeepLinkLifecycleObserver();

  static Future<void> init(List<String> launchArgs) async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

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
    final normalizedRaw = raw.trim();
    final now = DateTime.now();
    if (_lastHandledRaw == normalizedRaw &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastHandledRaw = normalizedRaw;
    _lastHandledAt = now;

    final uri = Uri.tryParse(normalizedRaw);
    if (uri == null || uri.scheme != scheme) return;
    _pendingUri = uri;
    await _tryConsumePending();
  }

  static Future<void> consumePendingAfterAppReady() {
    _appReady = true;
    return _tryConsumePending();
  }

  static Future<void> _readPendingNativeLink() async {
    if (_readingNativePending || kIsWeb || !Platform.isAndroid) return;
    _readingNativePending = true;
    try {
      final raw = await _channel.invokeMethod<String>('getInitialDeepLink');
      if (raw != null && raw.isNotEmpty) {
        await handleUriString(raw);
      }
    } catch (_) {
      // The native channel may be temporarily unavailable while the Flutter
      // Activity is being resumed. The next resume can retry safely.
    } finally {
      _readingNativePending = false;
    }
  }

  static Future<void> _tryConsumePending({int attempt = 0}) async {
    final uri = _pendingUri;
    if (uri == null) return;
    if (!_appReady) return;

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

    // 记账小组件：主体打开记账首页，快捷按钮直接打开「记一笔」。
    if (uri.host == 'finance') {
      final openQuickEntry = uri.pathSegments.contains('entry') ||
          uri.queryParameters['action'] == 'entry';
      navigator.push(
        PageTransitions.slideHorizontal(
          FinanceHomeScreen(
            username: username,
            openQuickEntry: openQuickEntry,
          ),
          settings: const RouteSettings(name: '/finance'),
        ),
      );
      return;
    }

    // 习惯中心（macOS 习惯小组件点击进入）。
    if (uri.host == 'habit') {
      navigator.push(
        PageTransitions.slideHorizontal(
          HabitCenterScreen(username: username),
        ),
      );
      return;
    }

    // 小组件快捷打卡（macOS 习惯小组件按钮 → AppIntent → 深链接）。
    if (uri.host == 'habitcheckin') {
      final habitId = uri.queryParameters['habitId']?.trim();
      if (habitId == null || habitId.isEmpty) return;
      final value = double.tryParse(uri.queryParameters['value'] ?? '');
      final result = await HabitWidgetCheckIn.quickCheckIn(
        habitId: habitId,
        value: value,
        username: username,
      );
      final todos = await StorageService.getTodos(username);
      unawaited(WidgetService.updateAllWidgetData(username, todos));
      if (result is HabitWidgetCheckInOpenApp) {
        // 时长型：进入习惯中心，由用户手动开始专注。
        navigator.push(
          PageTransitions.slideHorizontal(
            HabitCenterScreen(username: username),
          ),
        );
        return;
      }
      // 打卡后回到习惯中心给出视觉反馈（进入习惯中心即可见状态刷新）。
      navigator.push(
        PageTransitions.slideHorizontal(
          HabitCenterScreen(username: username),
        ),
      );
      return;
    }

    final recurrenceSeriesId = _recurrenceSeriesId(uri);
    if (recurrenceSeriesId != null) {
      final todos = await StorageService.getTodos(username);
      final seriesOccurrences = todos
          .where((todo) =>
              !todo.isDeleted && todo.recurrenceSeriesId == recurrenceSeriesId)
          .toList();
      if (seriesOccurrences.isEmpty) return;
      final selected = collapseRecurrenceSeriesForTodoPicker(
        seriesOccurrences,
        now: DateTime.now(),
      );
      if (selected.isEmpty) return;
      navigator.push(
        PageTransitions.slideHorizontal(
          TodoDetailScreen(todo: selected.first),
        ),
      );
      return;
    }

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

  static String? _recurrenceSeriesId(Uri uri) {
    final isRecurrenceTodo = uri.host == 'todo' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'recurrence';
    if (!isRecurrenceTodo) return null;
    final seriesId = uri.queryParameters['seriesId']?.trim();
    return seriesId == null || seriesId.isEmpty ? null : seriesId;
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
    } catch (_) {}
  }
}

class _AppDeepLinkLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AppDeepLinkService._readPendingNativeLink());
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
