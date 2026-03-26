import 'dart:async';
import 'dart:io';
// dart:convert removed
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
import '../windows_island/island_manager.dart';
import '../windows_island/island_channel.dart';

class FloatWindowService {
  // Channel used to communicate with a desktop multi-window host (guarded).
  // Use the same channel name as the desktop_multi_window plugin expects.
  static const _dmwChannel = MethodChannel('mixin.one/desktop_multi_window');

  static bool _initialized = false;
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      importIslandChannelAndSubscribe();
    } catch (_) {}
  }

  static void importIslandChannelAndSubscribe() {
    // Delayed import to avoid circular imports at file top-level
    try {
      // Ensure handler is set and subscribe to actions
      IslandChannel.ensureInitialized();
      IslandChannel.actionStream.listen((event) {
        try {
          final winId = event['windowId']?.toString();
          final action = event['action']?.toString();
          final payload = event['payload'] as Map<String, dynamic>?;
          debugPrint('[FloatWindow] Island action from $winId: $action payload=$payload');
          if (action == 'finish') {
            _handleAction('finish', payload?['modifiedSecs'] ?? 0);
          } else if (action == 'abandon') {
            _handleAction('abandon', 0);
          } else if (action == 'bounds_changed') {
            try {
              final bounds = payload?['bounds'] as Map<String, dynamic>?;
              if (bounds != null && winId != null) {
                StorageService.saveIslandBounds(winId, bounds);
                debugPrint('[FloatWindow] saved island bounds for $winId: $bounds');
              }
            } catch (e) {
              debugPrint('[FloatWindow] failed to save bounds: $e');
            }
          } else if (action == 'handshake_pong') {
            // Handshake pong received; IslandManager waiting logic will observe via stream
            debugPrint('[FloatWindow] handshake_pong from $winId');
          }
        } catch (e) {
          debugPrint('[FloatWindow] failed to handle island action: $e');
        }
      });
    } catch (_) {}
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

      // Convert to typed DTO (legacy) and build structured island payload
      final dto = () {
        try {
          return IslandPayload.fromMap(sanitized);
        } catch (_) {
          return IslandPayload.fromMap(null);
        }
      }();

      // Build structured payload following docs/island.md
      Map<String, dynamic> buildIslandStructuredPayload(IslandPayload p) {
        final bool isFocusing = p.endMs > 0;
        final state = isFocusing ? 'focusing' : 'idle';
        final focusData = {
          'title': p.title,
          'timeLabel': (() {
            if ((p.endMs ?? 0) > 0) {
              final now = DateTime.now().millisecondsSinceEpoch;
              final secs = ((p.endMs ?? 0) - now) ~/ 1000;
              final mm = (secs ~/ 60).toString().padLeft(2, '0');
              final ss = (secs % 60).toString().padLeft(2, '0');
              return '${mm}:${ss}';
            }
            return '';
          })(),
          'isCountdown': true,
          'tags': p.tags,
          'syncMode': p.isLocal ? 'local' : 'remote',
          'endMs': p.endMs ?? 0,
        };

        final reminderData = (p.reminderQueue.isNotEmpty)
            ? {
                'title': p.reminderQueue.first['text'] ?? '',
                'location': p.reminderQueue.first['type'] ?? '',
                'time': p.reminderQueue.first['timeLabel'] ?? '',
              }
            : {};

        final dashboardData = {
          'leftSlot': p.left ?? '',
          'rightSlot': p.right ?? '',
        };

                // Check whether host supports transparent windows for this island
                final bool transparentSupported = IslandManager().getTransparentSupport('island-1');

                return {
          'state': state,
          'theme': prefs.getString('theme') ?? 'system',
          'focusData': focusData,
          'reminderData': reminderData,
          'dashboardData': dashboardData,
                  'transparentSupported': transparentSupported,
          // include legacy flattened payload for compatibility
          'legacy': p.toMap(),
        };
      }

      print('[FloatWindow] showFloat payload: endMs=${payload['endMs']} mode=${payload['mode']} isLocal=${payload['isLocal']} style=${payload['style']} forceReset=${payload['forceReset']}');

      // If style==1 (灵动岛 / Island) try to deliver using Dart IslandManager
      final int styleInt = (payload['style'] is int) ? payload['style'] as int : 0;
      if (Platform.isWindows && styleInt == 1) {
        try {
          final islandId = 'island-1';
          // If no window cached, attempt to create (with cooldown)
          var winId = IslandManager().getCachedWindowId(islandId);

          if (winId == null) {
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            if (nowMs - _lastIslandCreateAttemptMs < _islandCreateCooldownMs) {
              debugPrint('[FloatWindow] creation cooldown active, checking if window appeared...');
              // If we skipped create but the window is now actually up, winId might still be null here
              // so we re-fetch from cache. 
              winId = IslandManager().getCachedWindowId(islandId);
            } else {
              _lastIslandCreateAttemptMs = nowMs;
              debugPrint('[FloatWindow] IslandManager.createIsland -> islandId=$islandId');
              winId = await IslandManager().createIsland(islandId);
            }
          }

          // If we have (or just created) a window id, post the structured payload
          if (winId != null) {
            final structured = buildIslandStructuredPayload(dto);
            // Optimization: if it's the first payload for a new window, send it
            // but createWindow already takes a payload. This is an extra push to be sure.
            final sent = await IslandManager().sendStructuredPayload(islandId, structured);
            if (sent) {
              debugPrint('[FloatWindow] posted structured payload to island window id=$winId');
              // Clear any in-layout debug payload when native island is active
              try { debugPayload.value = null; } catch (_) {}
              return;
            } else {
              debugPrint('[FloatWindow] IslandManager.postStructuredPayload failed for window id=$winId; clearing cache and will fallback');
              // clear cached id and allow fallback to legacy
              await IslandManager().recreateIsland(islandId);
            }
          }
        } catch (e) {
          debugPrint('[FloatWindow] IslandManager delivery failed: $e');
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
        return;
      }

      // Removed legacy delivery: ask native legacy float to show/update.
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

  // Protect against thrashing createWindow calls when native windows are
  // repeatedly created/destroyed. Record the last create attempt time and
  // enforce a short cooldown between attempts.
  static int _lastIslandCreateAttemptMs = 0;
  static const int _islandCreateCooldownMs = 1200;

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

