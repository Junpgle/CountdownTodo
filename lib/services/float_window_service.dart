import 'dart:async';
import 'dart:io';
// dart:convert removed
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../main.dart' show appNavigatorKey;
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

  static bool _processingAction = false;

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
          debugPrint(
              '[FloatWindow] Island action from $winId: $action payload=$payload');
          if (action == 'finish') {
            final modifiedSecs =
                event['modifiedSecs'] ?? payload?['modifiedSecs'] ?? 0;
            _handleAction('finish', (modifiedSecs is int) ? modifiedSecs : 0);
          } else if (action == 'abandon') {
            _handleAction('abandon', 0);
          } else if (action == 'reminder_ok') {
            // 提醒已确认，记录到存储
            final itemId = event['itemId']?.toString();
            if (itemId != null) {
              _saveAcknowledgedReminder(itemId);
            }
          } else if (action == 'remind_later') {
            // 打开主窗口并显示稍后提醒选择框
            _handleRemindLater();
          } else if (action == 'bounds_changed') {
            try {
              final bounds = payload?['bounds'] as Map<String, dynamic>?;
              if (bounds != null) {
                // Use a fixed logical ID for the primary island to ensure persistence stability
                StorageService.saveIslandBounds('island-1', bounds);
                debugPrint(
                    '[FloatWindow] saved island bounds for island-1: $bounds');
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

  /// 保存已确认的提醒 ID 到存储
  static Future<void> _saveAcknowledgedReminder(String itemId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'acknowledged_reminder_ids';
      final List<String> ids = prefs.getStringList(key) ?? [];
      if (!ids.contains(itemId)) {
        ids.add(itemId);
        await prefs.setStringList(key, ids);
        debugPrint('[FloatWindow] 已保存确认提醒 ID: $itemId');
      }
    } catch (e) {
      debugPrint('[FloatWindow] 保存确认提醒 ID 失败: $e');
    }
  }

  /// 处理稍后提醒 action
  static Future<void> _handleRemindLater() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.show();
      await windowManager.focus();

      // 稍后显示对话框，确保窗口已完全显示
      Timer(const Duration(milliseconds: 300), () {
        _showSnoozeDialog();
      });
    } catch (e) {
      debugPrint('[FloatWindow] 处理稍后提醒失败: $e');
    }
  }

  /// 显示稍后提醒选择对话框
  static void _showSnoozeDialog() {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;

    final TextEditingController customController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('稍后提醒'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSnoozeChip(dialogContext, '5 分钟', 5),
                _buildSnoozeChip(dialogContext, '10 分钟', 10),
                _buildSnoozeChip(dialogContext, '15 分钟', 15),
                _buildSnoozeChip(dialogContext, '30 分钟', 30),
                _buildSnoozeChip(dialogContext, '1 小时', 60),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: customController,
              decoration: const InputDecoration(
                labelText: '自定义时长（分钟）',
                border: OutlineInputBorder(),
                hintText: '输入 1-1440',
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (value) {
                final minutes = int.tryParse(value);
                if (minutes != null && minutes > 0 && minutes <= 1440) {
                  Navigator.of(dialogContext).pop(minutes);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final minutes = int.tryParse(customController.text);
              if (minutes != null && minutes > 0 && minutes <= 1440) {
                Navigator.of(dialogContext).pop(minutes);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((minutes) {
      customController.dispose();
      if (minutes != null && minutes is int) {
        // 安排新的提醒
        final triggerAt = DateTime.now().add(Duration(minutes: minutes));
        debugPrint('[FloatWindow] 安排稍后提醒: $minutes 分钟后');
        // TODO: 调用 NotificationService 安排提醒
      }
    });
  }

  static Widget _buildSnoozeChip(
      BuildContext context, String label, int minutes) {
    return ActionChip(
      label: Text(label),
      onPressed: () => Navigator.of(context).pop(minutes),
    );
  }

  // Development helper: when running in debug, allow an in-layout island
  // to be shown using the same update payload logic (does not create
  // a separate native window). This helps during development before
  // the desktop_multi_window integration is completed.
  static ValueNotifier<Map<String, dynamic>?> debugPayload =
      ValueNotifier(null);

  static bool isWorkbenchMounted = false;
  static int _actionVersion = 0;

  static void _handleAction(String action, int secs) async {
    if (_processingAction) {
      debugPrint('[FloatWindow] action $action ignored: already processing');
      return;
    }
    _processingAction = true;
    final int myVersion = ++_actionVersion;

    debugPrint(
        '[FloatWindow] _handleAction: action=$action, secs=$secs, isWorkbenchMounted=$isWorkbenchMounted');

    if (isWorkbenchMounted) {
      try {
        final isFocused = await windowManager.isFocused();
        if (isFocused) {
          debugPrint(
              '[FloatWindow] action $action skipped: workbench is focused');
          _processingAction = false;
          return;
        }
      } catch (_) {}
    }

    final saved = await PomodoroService.loadRunState();
    if (saved == null) {
      if (action == 'abandon') {
        await PomodoroService.clearRunState();
        clearFocus();
        await update(endMs: 0, isLocal: true);
      }
      _processingAction = false;
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. 立即清状态推岛
    await PomodoroService.clearRunState();
    clearFocus();
    await update(endMs: 0, isLocal: true);
    debugPrint('[FloatWindow] island updated to idle');

    // 2. 检查版本号：如果期间有新的 action，丢弃旧的记录保存
    if (_actionVersion != myVersion) {
      debugPrint('[FloatWindow] action $action stale, skipping record save');
      _processingAction = false;
      return;
    }

    // 3. 后台保存记录
    if (action == 'finish') {
      final isCountUp = saved.mode == TimerMode.countUp;
      final actualSecs =
          isCountUp ? secs : ((now - saved.sessionStartMs) ~/ 1000);

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
      PomodoroSyncService().sendStopSignal();

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
    } else if (action == 'abandon') {
      PomodoroSyncService().sendStopSignal();
    }

    debugPrint('[FloatWindow] $action done');
    _processingAction = false;
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
    print(
        '[FloatWindow] update called with endMs=$endMs title=$title tags=$tags isLocal=$isLocal mode=$mode forceReset=$forceReset');
    print(
        '[FloatWindow] prev snapshot _lastEndMs=$prevEndMsSnapshot _lastIsLocal=$prevIsLocalSnapshot _lastMode=$prevModeSnapshot');

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

    print(
        '[FloatWindow] resulting _lastEndMs=$_lastEndMs _lastIsLocal=$_lastIsLocal _lastMode=$_lastMode');

    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.reload();
    } catch (_) {}

    // Use float_window_style as the single source of truth:
    // 0 = classic (no island), 1 = island enabled, 2 = disabled
    final style = prefs.getInt('float_window_style') ?? 0;

    if (style != 1) {
      if (Platform.isWindows) {
        // Ensure any existing island window is destroyed when not in island mode
        try {
          await IslandManager().destroyCachedIsland('island-1');
        } catch (_) {}
      }
      return;
    }

    // Priority sorting system for island slots
    final defaultPriority = ['course', 'countdown', 'todo'];
    final priorityList =
        prefs.getStringList('island_slot_priority') ?? defaultPriority;

    String leftStr = '';
    String rightStr = '';
    Map<String, String> leftDetail = {};
    Map<String, String> rightDetail = {};

    if (style == 1) {
      // Collect top 2 non-empty valid slots
      List<Map<String, String>> validSlots = [];

      for (String pType in priorityList) {
        if (validSlots.length >= 2) break; // we only need left and right

        final slotData = await _getSlotData(pType, isLeft: validSlots.isEmpty);
        if ((slotData['display'] ?? '').isNotEmpty) {
          validSlots.add(slotData);
        }
      }

      if (validSlots.isNotEmpty) {
        leftDetail = validSlots[0];
        leftStr = leftDetail['display'] ?? '';
      }
      if (validSlots.length > 1) {
        rightDetail = validSlots[1];
        rightStr = rightDetail['display'] ?? '';
      }

      if (_lastEndMs == 0) {
        topBarLeft ??= leftStr;
        topBarRight ??= rightStr;
      } else {
        // Focus mode. topBarLeft and right remain fallback handled...
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
      print(
          '[FloatWindow] shouldForceReset=$shouldForceReset (prevEndMs=$prevEndMs now=$_lastEndMs)');

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
            ? (payload['tags'] as List)
                .map((e) => e?.toString() ?? '')
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[],
        'isLocal':
            (payload['isLocal'] is bool) ? payload['isLocal'] as bool : true,
        'mode': (payload['mode'] is int) ? payload['mode'] as int : 0,
        'style': (payload['style'] is int) ? payload['style'] as int : 0,
        'left': (payload['left'] is String) ? payload['left'] as String : '',
        'right': (payload['right'] is String) ? payload['right'] as String : '',
        'forceReset': (payload['forceReset'] is bool)
            ? payload['forceReset'] as bool
            : false,
        'topBarLeft': (payload['topBarLeft'] is String)
            ? payload['topBarLeft'] as String
            : '',
        'topBarRight': (payload['topBarRight'] is String)
            ? payload['topBarRight'] as String
            : '',
        'reminderQueue': (payload['reminderQueue'] is List)
            ? (payload['reminderQueue'] as List).map((item) {
                if (item is Map) {
                  return Map<String, String>.from(item.map(
                      (k, v) => MapEntry(k.toString(), v?.toString() ?? '')));
                }
                return <String, String>{};
              }).toList()
            : <Map<String, String>>[],
        'detail_type': (payload['detail_type'] is String)
            ? payload['detail_type'] as String
            : '',
        'detail_title': (payload['detail_title'] is String)
            ? payload['detail_title'] as String
            : '',
        'detail_subtitle': (payload['detail_subtitle'] is String)
            ? payload['detail_subtitle'] as String
            : '',
        'detail_location': (payload['detail_location'] is String)
            ? payload['detail_location'] as String
            : '',
        'detail_time': (payload['detail_time'] is String)
            ? payload['detail_time'] as String
            : '',
        'detail_note': (payload['detail_note'] is String)
            ? payload['detail_note'] as String
            : '',
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
            if (p.endMs > 0) {
              final now = DateTime.now().millisecondsSinceEpoch;
              int secs;
              if (p.mode == 1) {
                // Count-up: endMs represents the start time
                secs = (now - p.endMs) ~/ 1000;
              } else {
                // Count-down: endMs represents the target end time
                secs = (p.endMs - now) ~/ 1000;
              }
              if (secs < 0) secs = 0;
              final mm = (secs ~/ 60).toString().padLeft(2, '0');
              final ss = (secs % 60).toString().padLeft(2, '0');
              return '${mm}:${ss}';
            }
            return '';
          })(),
          'isCountdown': p.mode != 1,
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
          'leftSlot': (p.topBarLeft.isNotEmpty) ? p.topBarLeft : p.left,
          'rightSlot': (p.topBarRight.isNotEmpty) ? p.topBarRight : p.right,
        };

        // Check whether host supports transparent windows for this island
        final bool transparentSupported =
            IslandManager().getTransparentSupport('island-1');

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

      print(
          '[FloatWindow] showFloat payload: endMs=${payload['endMs']} mode=${payload['mode']} isLocal=${payload['isLocal']} style=${payload['style']} forceReset=${payload['forceReset']}');

      // If style==1 (灵动岛 / Island) try to deliver using Dart IslandManager
      final int styleInt =
          (payload['style'] is int) ? payload['style'] as int : 0;
      if (Platform.isWindows && styleInt == 1) {
        try {
          final islandId = 'island-1';
          // If no window cached, attempt to create (with cooldown)
          var winId = IslandManager().getCachedWindowId(islandId);

          if (winId == null) {
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            if (nowMs - _lastIslandCreateAttemptMs < _islandCreateCooldownMs) {
              debugPrint(
                  '[FloatWindow] creation cooldown active, checking if window appeared...');
              // If we skipped create but the window is now actually up, winId might still be null here
              // so we re-fetch from cache.
              winId = IslandManager().getCachedWindowId(islandId);
            } else {
              _lastIslandCreateAttemptMs = nowMs;
              debugPrint(
                  '[FloatWindow] IslandManager.createIsland -> islandId=$islandId');
              winId = await IslandManager().createIsland(islandId);
            }
          }

          // If we have (or just created) a window id, post the structured payload
          if (winId != null) {
            final structured = buildIslandStructuredPayload(dto);
            debugPrint(
                '[FloatWindow] 发送 payload 到岛: state=${structured['state']}, endMs=${(structured['focusData'] as Map?)?['endMs']}, timeLabel=${(structured['focusData'] as Map?)?['timeLabel']}');
            debugPrint(
                '[FloatWindow] about to send to island: state=${structured['state']}');
            final sent = await IslandManager()
                .sendStructuredPayload(islandId, structured);
            debugPrint(
                '[FloatWindow] send result: $sent, state sent=${structured['state']}');
            if (sent) {
              debugPrint(
                  '[FloatWindow] posted structured payload to island window id=$winId');
              // Clear any in-layout debug payload when native island is active
              try {
                debugPayload.value = null;
              } catch (_) {}
              return;
            } else {
              debugPrint(
                  '[FloatWindow] sendStructuredPayload failed for window id=$winId');
            }
          }
        } catch (e) {
          debugPrint('[FloatWindow] IslandManager delivery failed: $e');
        }
      }

      // style==2 (disabled) is now handled by the early-return at the top of update()

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
          final time =
              t.dueDate != null ? DateFormat('MM-dd').format(t.dueDate!) : '';
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
                  final endHour = c.endTime ~/ 100;
                  final endMin = c.endTime % 100;
                  final courseEnd =
                      DateTime(now.year, now.month, now.day, endHour, endMin);
                  return now.isBefore(courseEnd);
                }
                return true;
              }).toList();

              if (valid.isNotEmpty) {
                final c = valid.first as CourseItem;

                // ✅ 判断课程是否正在进行
                final startHour = c.startTime ~/ 100;
                final startMin = c.startTime % 100;
                final courseStart =
                    DateTime(now.year, now.month, now.day, startHour, startMin);

                final bool isOngoing = now.isAfter(courseStart);

                final time =
                    isOngoing ? c.formattedEndTime : c.formattedStartTime;
                final timeLabel = isOngoing ? '结束' : '开始';

                final display = isLeft
                    ? '[$time] ${c.courseName}'
                    : '${c.courseName} [$time]';

                return {
                  'display': display,
                  'type': 'course',
                  'detail_title': c.courseName,
                  'detail_subtitle': c.teacherName,
                  'detail_location': c.roomName,
                  'detail_time': '$time$timeLabel',
                  'detail_note': '',
                };
              }
            }
          } catch (_) {}
          return {'display': '', 'type': 'course'};
        case 'record':
          try {
            final records = await PomodoroService.getRecords();
            if (records.isNotEmpty) {
              final r = records.first;
              final time = DateFormat('HH:mm').format(
                  DateTime.fromMillisecondsSinceEpoch(
                      r.endTime ?? r.startTime));
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
            final active = cds
                .where((c) => !c.isDeleted && c.targetDate.isAfter(now))
                .toList();
            active.sort((a, b) => a.targetDate.compareTo(b.targetDate));
            if (active.isNotEmpty) {
              final c = active.first;
              final days = c.targetDate.difference(now).inDays;
              final info = '${days}天';
              final display =
                  isLeft ? '[$info] ${c.title}' : '${c.title} [$info]';
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
      final active = todos
          .where((t) => !t.isDone && !t.isDeleted && t.dueDate != null)
          .toList();
      for (var t in active) {
        if (t.dueDate!.year == now.year &&
            t.dueDate!.month == now.month &&
            t.dueDate!.day == now.day) {
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
            await windowManager.setBounds(
                Rect.fromLTWH(b.left, newTop.toDouble(), b.width, b.height));
          } catch (_) {}
          await windowManager.focus();
        } catch (_) {}
      }

      // Instruct native float implementation to reset its position.
      if (Platform.isWindows) {
        final islandId = 'island-1';
        final winId = IslandManager().getCachedWindowId(islandId);
        if (winId != null) {
          try {
            // Default island pill size (Idle state)
            const double w = 160.0;
            const double h = 56.0;

            int left, top;
            try {
              // Center relative to the main window (which was just centered)
              // This ensures it appears in the middle of the active monitor.
              final mb = await windowManager.getBounds();
              left = (mb.left + (mb.width - w) / 2).toInt();
              top = (mb.top + (mb.height - h) / 2).toInt();
            } catch (e) {
              // Absolute fallback
              left = 100;
              top = 100;
            }

            // Move the window to the center
            await IslandChannel.setWindowBounds(winId, {
              'left': left,
              'top': top,
              'width': w.toInt(),
              'height': h.toInt(),
            });

            debugPrint(
                '[FloatWindow] Reset island position to center: $left, $top');
          } catch (e) {
            debugPrint('[FloatWindow] Failed to reset island position: $e');
          }
        }
      }

      // Trigger a refresh/update to ensure state is synchronized
      try {
        await update(forceReset: true);
      } catch (_) {}
    } catch (_) {}
  }
}
