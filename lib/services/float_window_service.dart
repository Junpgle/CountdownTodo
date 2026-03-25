import 'dart:async';
import 'dart:io';
import 'dart:convert';
// dart:convert not required here
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../storage_service.dart';
import 'course_service.dart';
import 'pomodoro_service.dart';
import 'pomodoro_sync_service.dart';
import '../windows_island/island_payload.dart';

class FloatWindowService {
  static const _channel = MethodChannel('com.math_quiz_app/float_window');
  // Channel used to communicate with a desktop multi-window host (guarded).
  // Use the same channel name as the desktop_multi_window plugin expects.
  static const _dmwChannel = MethodChannel('mixin.one/desktop_multi_window');

  static bool _initialized = false;
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final action = call.arguments['action'];
        final modifiedSecs = call.arguments['modifiedSecs'];
        if (action == 'finish') {
          _handleAction('finish', modifiedSecs);
        } else if (action == 'abandon') {
          _handleAction('abandon', 0);
        }
      }
    });
  }

  // Development helper: when running in debug, allow an in-layout island
  // to be shown using the same update payload logic (does not create
  // a separate native window). This helps during development before
  // the desktop_multi_window integration is completed.
  static ValueNotifier<Map<String, dynamic>?> debugPayload = ValueNotifier(null);

  static void _handleAction(String action, int secs) async {
    print('FloatWindow Action: $action, secs: $secs');
    
    final saved = await PomodoroService.loadRunState();
    if (saved == null) {
      if (action == 'abandon') {
         await PomodoroService.clearRunState();
         await _channel.invokeMethod('hideFloat');
      }
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    
    if (action == 'abandon') {
      await PomodoroService.clearRunState();
      PomodoroSyncService().sendStopSignal();
      clearFocus();
    } else if (action == 'finish') {
      final isCountUp = saved.mode == TimerMode.countUp;
      final actualSecs = isCountUp ? secs : ((now - saved.sessionStartMs) ~/ 1000);

      final record = PomodoroRecord(
        uuid: saved.sessionUuid,
        todoUuid: saved.todoUuid,
        todoTitle: saved.todoTitle,
        tagUuids: saved.tagUuids,
        startTime: saved.sessionStartMs,
        endTime: now,
        plannedDuration: saved.plannedFocusSeconds,
        actualDuration: actualSecs,
        status: PomodoroRecordStatus.completed,
      );
      
      await PomodoroService.addRecord(record);
      await PomodoroService.clearRunState();
      PomodoroSyncService().sendStopSignal();
      clearFocus();
      
      if (saved.todoUuid != null && saved.todoUuid!.isNotEmpty) {
        final username = await StorageService.getLoginSession() ?? 'default';
        final allTodos = await StorageService.getTodos(username);
        final idx = allTodos.indexWhere((t) => t.id == saved.todoUuid);
        if (idx != -1) {
          allTodos[idx].isDone = true;
          allTodos[idx].markAsChanged();
          await StorageService.saveTodos(username, allTodos);
        }
      }
    }
    
    await update();
  }


  static int _lastEndMs = 0;
  static String _lastTitle = '';
  static List<String> _lastTags = const [];
  static bool _lastIsLocal = true;
  static int _lastMode = 0;

  static void clearFocus() {
    _lastEndMs = 0;
    _lastTitle = '';
    _lastTags = const [];
    _lastIsLocal = true;
    _lastMode = 0;
  }

  static Future<void> update({
    int? endMs,
    String? title,
    List<String>? tags,
    bool? isLocal,
    int? mode,
    bool forceReset = false,
    String? topBarLeft,
    String? topBarRight,
    List<Map<String, String>>? reminderQueue,
    bool includeReminders = false, // do not load reminders by default
  }) async {
    if (!Platform.isWindows) return;

    // Snapshot previous cached values (before any modification)
    final prevEndMsSnapshot = _lastEndMs;
    final prevIsLocalSnapshot = _lastIsLocal;
    final prevModeSnapshot = _lastMode;

    // Debug: log incoming request and previous cached state
    print('[FloatWindow] update called with endMs=$endMs title=$title tags=$tags isLocal=$isLocal mode=$mode forceReset=$forceReset');
    print('[FloatWindow] prev snapshot _lastEndMs=$prevEndMsSnapshot _lastIsLocal=$prevIsLocalSnapshot _lastMode=$prevModeSnapshot');

    if (endMs != null) {
      if (endMs == 0) {
        // Clear intent: only perform clear if caller explicitly passed isLocal.
        // This avoids accidental clearing due to races or generic no-arg refreshes.
        if (isLocal != null) {
          clearFocus();
        } else {
          // No explicit clear requested; keep last-known session values.
        }
      } else {
        // Ongoing session: update cached values. Preserve previous values for
        // fields callers didn't provide (null) to avoid accidental overwrites.
        _lastEndMs = endMs;
        _lastTitle = title ?? _lastTitle;
        _lastTags = tags ?? _lastTags;
        _lastIsLocal = isLocal ?? _lastIsLocal;
        _lastMode = mode ?? _lastMode;
      }
    } else {
      // No explicit endMs provided: keep the last-known session values.
      // (Some callers call update() without args to force a re-send.)
    }

    print('[FloatWindow] resulting _lastEndMs=$_lastEndMs _lastIsLocal=$_lastIsLocal _lastMode=$_lastMode');


    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.reload();
    } catch (_) {}

    if (!(prefs.getBool('float_window_enabled') ?? true)) {
      try {
        await _channel.invokeMethod('hideFloat');
      } catch (_) {}
      return;
    }

    final style = prefs.getInt('float_window_style') ?? 0;
    final leftType = prefs.getString('float_window_left_slot') ?? 'countdown';
    final rightType = prefs.getString('float_window_right_slot') ?? 'todo';

    String leftStr = '';
    String rightStr = '';
    Map<String, String> leftDetail = {};
    Map<String, String> rightDetail = {};

    if (style == 1) {
      if (_lastEndMs == 0) {
        // When idle and not explicitly requested, avoid loading reminder/slot data
        // to prevent noisy reminders on startup or when toggling settings.
        if (includeReminders) {
          final cdData = await _getSlotData('countdown', isLeft: true);
          final courseData = await _getSlotData('course', isLeft: false);
          topBarLeft ??= cdData['display'] ?? '';
          topBarRight ??= courseData['display'] ?? '';
          leftDetail = cdData; // Default detail for TopBar
        } else {
          topBarLeft ??= '';
          topBarRight ??= '';
          leftDetail = {};
        }
      } else {
        // Focus mode or legacy slot behavior
        leftDetail = await _getSlotData(leftType, isLeft: true);
        rightDetail = await _getSlotData(rightType, isLeft: false);
        leftStr = leftDetail['display'] ?? '';
        rightStr = rightDetail['display'] ?? '';
      }
    }
    
    // Aggregate reminders only if explicitly requested
    if (reminderQueue == null) {
      if (includeReminders) {
        reminderQueue = await _getReminderQueue();
      } else {
        reminderQueue = <Map<String, String>>[];
      }
    }

    // Choose which slot to use for detail card (prefer left, fallback to right)
    final detailSource = leftDetail.isNotEmpty ? leftDetail : rightDetail;

    // Snapshot previous endMs to detect transitions (idle -> active)
    final prevEndMs = prevEndMsSnapshot;

    try {
      final shouldForceReset = forceReset || (prevEndMs == 0 && _lastEndMs > 0);
      print('[FloatWindow] shouldForceReset=$shouldForceReset (prevEndMs=$prevEndMs now=$_lastEndMs)');

      final payload = <String, Object>{
        'endMs': _lastEndMs,
        'title': _lastTitle,
        'tags': _lastTags,
        'isLocal': _lastIsLocal,
        'mode': _lastMode,
        'style': style,
        'left': leftStr,
        'right': rightStr,
        'forceReset': shouldForceReset,
        'topBarLeft': topBarLeft ?? '',
        'topBarRight': topBarRight ?? '',
        'reminderQueue': reminderQueue,
        // Detail card data
        'detail_type': detailSource['type'] ?? '',
        'detail_title': detailSource['detail_title'] ?? '',
        'detail_subtitle': detailSource['detail_subtitle'] ?? '',
        'detail_location': detailSource['detail_location'] ?? '',
        'detail_time': detailSource['detail_time'] ?? '',
        'detail_note': detailSource['detail_note'] ?? '',
      };

      // Sanitize payload to ensure native side receives well-typed values.
      final sanitized = <String, Object>{
        'endMs': (payload['endMs'] is int) ? payload['endMs'] as int : 0,
        'title': (payload['title'] is String) ? payload['title'] as String : '',
        'tags': (payload['tags'] is List)
            ? (payload['tags'] as List).map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList()
            : <String>[],
        'isLocal': (payload['isLocal'] is bool) ? payload['isLocal'] as bool : true,
        'mode': (payload['mode'] is int) ? payload['mode'] as int : 0,
        'style': (payload['style'] is int) ? payload['style'] as int : 0,
        'left': (payload['left'] is String) ? payload['left'] as String : '',
        'right': (payload['right'] is String) ? payload['right'] as String : '',
        'forceReset': (payload['forceReset'] is bool) ? payload['forceReset'] as bool : false,
        'topBarLeft': (payload['topBarLeft'] is String) ? payload['topBarLeft'] as String : '',
        'topBarRight': (payload['topBarRight'] is String) ? payload['topBarRight'] as String : '',
        'reminderQueue': (payload['reminderQueue'] is List)
            ? (payload['reminderQueue'] as List).map((item) {
                if (item is Map) {
                  return Map<String, String>.from(item.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')));
                }
                return <String, String>{};
              }).toList()
            : <Map<String, String>>[],
        'detail_type': (payload['detail_type'] is String) ? payload['detail_type'] as String : '',
        'detail_title': (payload['detail_title'] is String) ? payload['detail_title'] as String : '',
        'detail_subtitle': (payload['detail_subtitle'] is String) ? payload['detail_subtitle'] as String : '',
        'detail_location': (payload['detail_location'] is String) ? payload['detail_location'] as String : '',
        'detail_time': (payload['detail_time'] is String) ? payload['detail_time'] as String : '',
        'detail_note': (payload['detail_note'] is String) ? payload['detail_note'] as String : '',
      };

      // Convert to typed DTO
      final dto = () {
        try {
          // Lazily import DTO to avoid circular imports at top-level
          return IslandPayload.fromMap(sanitized);
        } catch (_) {
          return IslandPayload.fromMap(null);
        }
      }();

      print('[FloatWindow] showFloat payload: endMs=${payload['endMs']} mode=${payload['mode']} isLocal=${payload['isLocal']} style=${payload['style']} forceReset=${payload['forceReset']}');

      // If style==1 (灵动岛 / Island) try to send payload to desktop multi-window host first.
      final int styleInt = (payload['style'] is int) ? payload['style'] as int : 0;
      if (Platform.isWindows && styleInt == 1 && _dmwAvailable) {
        // Helper to attempt desktop_multi_window invocations with retries and
        // consistent MissingPluginException handling.
        Future<dynamic> dmwInvoke(String method, dynamic arguments,
            {int attempts = 2, Duration timeout = const Duration(milliseconds: 2000)}) async {
          for (int i = 0; i < attempts; i++) {
            try {
              debugPrint('[FloatWindow] desktop_multi_window.invoke -> $method (attempt ${i + 1})');
              final resFuture = _dmwChannel.invokeMethod(method, arguments);
              final res = await resFuture.timeout(timeout, onTimeout: () => null);
              return res;
            } on MissingPluginException catch (mp) {
              debugPrint('[FloatWindow] desktop_multi_window MissingPluginException on $method: $mp');
              _dmwAvailable = false;
              return null;
            } catch (e) {
              debugPrint('[FloatWindow] desktop_multi_window invoke error on $method attempt ${i + 1}: $e');
              // retry unless last attempt
              if (i == attempts - 1) return null;
              await Future.delayed(const Duration(milliseconds: 120));
            }
          }
          return null;
        }

        try {
          // Avoid concurrent createWindow races. If another flow is already
          // creating the island, wait briefly for it to finish and reuse the
          // produced window id instead of creating a duplicate window.
          if (_islandWindowId == null) {
            if (_creatingIsland) {
              // Wait up to ~2s for the other creator to finish.
              final end = DateTime.now().add(const Duration(milliseconds: 2000));
              while (_creatingIsland && DateTime.now().isBefore(end)) {
                await Future.delayed(const Duration(milliseconds: 80));
              }
            }

            // If another task created the island while we waited, try posting to it.
            if (_islandWindowId != null) {
              final postRes = await dmwInvoke('postWindowMessage', {'windowId': _islandWindowId, 'payload': dto.toMap()}, attempts: 2, timeout: const Duration(milliseconds: 2000));
                if (postRes != null) {
                    debugPrint('[FloatWindow] posted payload to island window id=$_islandWindowId');
                    return;
                  } else {
                    debugPrint('[FloatWindow] desktop_multi_window.postWindowMessage returned null/timeout; clearing cached island id=$_islandWindowId');
                    // The target window may have been closed on the native side; clear
                    // the cached id so subsequent updates will attempt to recreate it.
                    _islandWindowId = null;
                  }
                }

            // Otherwise, attempt to create the island window (mark that we're creating)
            _creatingIsland = true;
            try {
              debugPrint('[FloatWindow] desktop_multi_window.createWindow -> arguments=islandMain');
              final res = await dmwInvoke('createWindow', {
                'arguments': 'islandMain',
                'hiddenAtLaunch': false,
                'payload': dto.toMap(),
              }, attempts: 2, timeout: const Duration(milliseconds: 2000));
              if (res is String && res.isNotEmpty) {
                _islandWindowId = res;
                debugPrint('[FloatWindow] created island window id=$_islandWindowId');
                return; // delivered to multi-window host
              } else {
                debugPrint('[FloatWindow] desktop_multi_window.createWindow returned null/timeout or unexpected: $res');
              }
            } finally {
              _creatingIsland = false;
            }
          } else {
            final postRes = await dmwInvoke('postWindowMessage', {'windowId': _islandWindowId, 'payload': dto.toMap()}, attempts: 2, timeout: const Duration(milliseconds: 2000));
            if (postRes != null) {
              debugPrint('[FloatWindow] posted payload to island window id=$_islandWindowId');
              return;
            } else {
              debugPrint('[FloatWindow] desktop_multi_window.postWindowMessage returned null/timeout; clearing cached island id=$_islandWindowId');
              _islandWindowId = null;
            }
          }
        } catch (e) {
          debugPrint('[FloatWindow] desktop_multi_window delivery failed: $e');
        }
      }

      // If style==2 (关闭), try to ensure any native windows are hidden/closed.
      if (Platform.isWindows && styleInt == 2) {
        try {
          // Try to close island window if we have an id
          if (_islandWindowId != null) {
            try {
              await _dmwChannel
                  .invokeMethod('closeWindow', {'windowId': _islandWindowId})
                  .timeout(const Duration(milliseconds: 600), onTimeout: () => null);
            } catch (_) {}
            _islandWindowId = null;
          }
        } catch (_) {}
        try {
          await _channel.invokeMethod('hideFloat');
        } catch (_) {}
        return;
      }

      // Legacy delivery: ask native legacy float to show/update. Also guard with timeout
      try {
        if (_disableLegacyFloat) {
          debugPrint('[FloatWindow] legacy showFloat disabled for diagnostics. payload: ${dto.toMap()}');
        } else {
          await _channel.invokeMethod('showFloat', dto.toMap()).timeout(const Duration(milliseconds: 800), onTimeout: () => null);
        }
      } catch (e) {
        debugPrint('[FloatWindow] legacy showFloat failed: $e');
      }
    } catch (e) {
      // Ignore errors if the window isn't ready or other issues
    }
  }

  // Cached island window id (if created via desktop_multi_window). The plugin
  // returns a string id for windows, not an int.
  static String? _islandWindowId;
  // Guard to avoid concurrent createWindow races
  static bool _creatingIsland = false;
  // Whether desktop_multi_window appears to be available in this runtime.
  // If we detect MissingPluginException or repeated timeouts, mark false
  // to avoid repeated blocking attempts.
  static bool _dmwAvailable = true;

  // Diagnostic: when true, skip calling the legacy native showFloat method.
  // Set to false in normal runs so the legacy native float (windows) is used
  // when desktop_multi_window is unavailable.
  static const bool _disableLegacyFloat = false;
  /// Returns structured data for a given slot type
  static Future<Map<String, String>> _getSlotData(String type,
      {required bool isLeft}) async {
    final username = await StorageService.getLoginSession() ?? 'default';
    try {
      switch (type) {
        case 'todo':
          final todos = await StorageService.getTodos(username);
          final active = todos.where((t) => !t.isDone && !t.isDeleted).toList();
          if (active.isEmpty) return {'display': '无待办', 'type': 'todo'};
          active.sort((a, b) {
            if (a.dueDate == null && b.dueDate == null)
              return b.createdAt.compareTo(a.createdAt);
            if (a.dueDate == null) return 1;
            if (b.dueDate == null) return -1;
            return a.dueDate!.compareTo(b.dueDate!);
          });
          final t = active.first;
          final time = t.dueDate != null ? DateFormat('MM-dd').format(t.dueDate!) : '';
          final display = isLeft
              ? (time.isNotEmpty ? '[$time] ${t.title}' : t.title)
              : (time.isNotEmpty ? '${t.title} [$time]' : t.title);

          String timeRange = '';
          if (t.dueDate != null) {
            timeRange = DateFormat('HH:mm').format(t.dueDate!);
          }

          return {
            'display': display,
            'type': 'todo',
            'detail_title': t.title,
            'detail_subtitle': t.remark ?? '',
            'detail_location': '',
            'detail_time': timeRange,
            'detail_note': time.isNotEmpty ? time : '',
          };
        case 'course':
          try {
            final dashboard = await CourseService.getDashboardCourses();
            final courses = dashboard['courses'] as List?;
            if (courses != null && courses.isNotEmpty) {
              final now = DateTime.now();
              final valid = courses.where((c) {
                if (c is! CourseItem) return false;
                if (dashboard['title'] == '今日课程') {
                  return (8 + (c.startTime - 1)) >= now.hour;
                }
                return true;
              }).toList();

              if (valid.isNotEmpty) {
                final c = valid.first as CourseItem;
                final time = c.formattedStartTime;
                final display = isLeft ? '[$time] ${c.courseName}' : '${c.courseName} [$time]';
                return {
                  'display': display,
                  'type': 'course',
                  'detail_title': c.courseName,
                  'detail_subtitle': c.teacherName,
                  'detail_location': c.roomName,
                  'detail_time': '${c.formattedStartTime}开始',
                  'detail_note': '',
                };
              }
            }
          } catch (_) {}
          return {'display': '无课程', 'type': 'course'};
        case 'record':
          try {
            final records = await PomodoroService.getRecords();
            if (records.isNotEmpty) {
              final r = records.first;
              final time = DateFormat('HH:mm')
                  .format(DateTime.fromMillisecondsSinceEpoch(r.endTime ?? r.startTime));
              final title = r.todoTitle ?? '专注';
              return {
                'display': isLeft ? '[$time] $title' : '$title [$time]',
                'type': 'record',
                'detail_title': title,
                'detail_subtitle': '',
                'detail_location': '',
                'detail_time': time,
                'detail_note': '',
              };
            }
          } catch (_) {}
          return {'display': '无记录', 'type': 'record'};
        case 'countdown':
          try {
            final cds = await StorageService.getCountdowns(username);
            final now = DateTime.now();
            final active = cds.where((c) => !c.isDeleted && c.targetDate.isAfter(now)).toList();
            active.sort((a, b) => a.targetDate.compareTo(b.targetDate));
            if (active.isNotEmpty) {
              final c = active.first;
              final days = c.targetDate.difference(now).inDays;
              final info = '${days}天';
              final display = isLeft ? '[$info] ${c.title}' : '${c.title} [$info]';
              return {
                'display': display,
                'type': 'countdown',
                'detail_title': c.title,
                'detail_subtitle': '',
                'detail_location': '',
                'detail_time': DateFormat('yyyy-MM-dd').format(c.targetDate),
                'detail_note': '还有${days}天',
              };
            }
          } catch (_) {}
          return {'display': '专注时钟', 'type': 'countdown'};
        default:
          return {'display': '', 'type': type};
      }
    } catch (_) {
      return {'display': '', 'type': type};
    }
  }

  /// Returns a list of simple reminder items for the float window (short list)
  static Future<List<Map<String, String>>> _getReminderQueue() async {
    final queue = <Map<String, String>>[];
    try {
      final username = await StorageService.getLoginSession() ?? 'default';
      // Upcoming todos for today
      final todos = await StorageService.getTodos(username);
      final now = DateTime.now();
      final active = todos.where((t) => !t.isDone && !t.isDeleted && t.dueDate != null).toList();
      for (var t in active) {
        if (t.dueDate!.year == now.year && t.dueDate!.month == now.month && t.dueDate!.day == now.day) {
          queue.add({
            'text': t.title,
            'type': 'todo',
            'timeLabel': DateFormat('HH:mm').format(t.dueDate!),
          });
        }
      }
    } catch (_) {}

    return queue;
  }

  /// Attempts to bring both the main window and the float window back into visible area.
  /// Centers the main app window (desktop) and asks native float window to force reset.
  static Future<void> resetPositions() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        try {
          // Center the main window so it's visible
          await windowManager.ensureInitialized();
          await windowManager.center();
          // After centering, nudge upward so window sits at upper area instead of exact center
          try {
            final b = await windowManager.getBounds();
            final newTop = (b.top - 120).toInt();
            await windowManager.setBounds(Rect.fromLTWH(b.left, newTop.toDouble(), b.width, b.height));
          } catch (_) {
            // fallback to focus if bounds APIs are not available
          }
          await windowManager.focus();
        } catch (_) {
          // ignore window_manager errors
        }
      }
      // Instruct native float implementation to reset its position.
      // Use our update() so the payload contains the current cached session
      // fields (style/endMs/isLocal/mode). Calling native directly with only
      // {'forceReset':true} would cause native to receive default style=0
      // and reset window size to Classic defaults.
      try {
        await update(forceReset: true);
      } catch (_) {}
    } catch (_) {}
  }
}

