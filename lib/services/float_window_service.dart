import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show appNavigatorKey;
import '../storage_service.dart';
import 'pomodoro_service.dart';
import 'pomodoro_sync_service.dart';
import '../windows_island/island_payload.dart';
import '../windows_island/island_manager.dart';
import '../windows_island/island_channel.dart';
import 'clipboard_service.dart';
import 'snooze_dialog.dart';
import 'island_slot_provider.dart';

/// Configuration constants for FloatWindowService
class FloatWindowConfig {
  FloatWindowConfig._();

  /// Cooldown between island creation attempts (ms)
  static const int islandCreateCooldownMs = 1200;

  /// Delay before showing snooze dialog (ms)
  static const int snoozeDialogDelayMs = 500;

  /// Default island window dimensions
  static const double defaultIslandWidth = 160.0;
  static const double defaultIslandHeight = 56.0;
}

/// Service for managing the floating window (island) integration.
/// Handles clipboard monitoring, action processing, and island communication.
class FloatWindowService {
  static const _dmwChannel = MethodChannel('mixin.one/desktop_multi_window');

  static bool _processingAction = false;
  static ClipboardService? _clipboardService;
  static String? _lastCopiedUrl;
  static bool _initialized = false;

  // Development helper for in-layout island testing
  static ValueNotifier<Map<String, dynamic>?> debugPayload =
      ValueNotifier(null);
  static bool isWorkbenchMounted = false;

  // Action processing state
  static int _actionVersion = 0;
  static int _lastEndMs = 0;
  static String _lastTitle = '';
  static List<String> _lastTags = const [];
  static bool _lastIsLocal = true;
  static int _lastMode = 0;

  // Island creation throttling
  static int _lastIslandCreateAttemptMs = 0;

  /// Initialize the service
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _initIslandChannelSubscription();
    } catch (_) {}
    _initClipboardListener();
  }

  // ── Clipboard Integration ──────────────────────────────────────────────

  static void _initClipboardListener() {
    debugPrint('[FloatWindow] _initClipboardListener called');
    _clipboardService = ClipboardService();
    _clipboardService!.startListening();
    _clipboardService!.onUrlCopied.listen((url) {
      debugPrint('[FloatWindow] URL received from stream: $url');
      if (url == _lastCopiedUrl) return;
      _lastCopiedUrl = url;
      _showCopiedLinkIsland(url);
    });
  }

  static Future<void> _showCopiedLinkIsland(String url) async {
    try {
      final displayUrl = _truncateUrlForDisplay(url);
      debugPrint('[FloatWindow] Attempting to send payload for: $displayUrl');

      final payload = {
        'state': 'copied_link',
        'copiedLinkData': {
          'url': url,
          'displayUrl': displayUrl,
        },
      };

      final winId = IslandManager().getCachedWindowId('island-1');
      debugPrint('[FloatWindow] island-1 windowId: $winId');

      if (winId == null) {
        debugPrint('[FloatWindow] Island not found, attempting to create');
        await IslandManager().createIsland('island-1');
      }

      await IslandManager().sendStructuredPayload('island-1', payload);
      debugPrint('[FloatWindow] Sent copied_link payload: $displayUrl');
    } catch (e) {
      debugPrint('[FloatWindow] Failed to show copied link island: $e');
    }
  }

  static String _truncateUrlForDisplay(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.length > 20) {
        return '${host.substring(0, 20)}...';
      }
      return host;
    } catch (_) {
      if (url.length > 25) {
        return '${url.substring(0, 25)}...';
      }
      return url;
    }
  }

  // ── Island Channel Subscription ────────────────────────────────────────

  static void _initIslandChannelSubscription() {
    try {
      IslandChannel.ensureInitialized();
      IslandChannel.actionStream.listen((event) {
        _handleIslandAction(event);
      });
    } catch (_) {}
  }

  static void _handleIslandAction(Map<String, dynamic> event) {
    try {
      final winId = event['windowId']?.toString();
      final action = event['action']?.toString();
      final payload = event['payload'] as Map<String, dynamic>?;
      debugPrint('[FloatWindow] Island action from $winId: $action');

      switch (action) {
        case 'finish':
          final modifiedSecs =
              event['modifiedSecs'] ?? payload?['modifiedSecs'] ?? 0;
          _handleAction('finish', (modifiedSecs is int) ? modifiedSecs : 0);
          break;
        case 'abandon':
          _handleAction('abandon', 0);
          break;
        case 'reminder_ok':
          final reminderData =
              payload?['reminderPopupData'] as Map<String, dynamic>?;
          final itemId = reminderData?['itemId']?.toString() ??
              event['itemId']?.toString();
          if (itemId != null) {
            _saveAcknowledgedReminder(itemId);
          }
          break;
        case 'remind_later':
          _handleRemindLater();
          break;
        case 'bounds_changed':
          final bounds = payload?['bounds'] as Map<String, dynamic>?;
          if (bounds != null) {
            StorageService.saveIslandBounds('island-1', bounds);
          }
          break;
        case 'handshake_pong':
          debugPrint('[FloatWindow] handshake_pong from $winId');
          break;
      }
    } catch (e) {
      debugPrint('[FloatWindow] Failed to handle island action: $e');
    }
  }

  // ── Reminder Handling ──────────────────────────────────────────────────

  static Future<void> _saveAcknowledgedReminder(String itemId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'acknowledged_reminder_ids';
      final List<String> ids = prefs.getStringList(key) ?? [];
      if (!ids.contains(itemId)) {
        ids.add(itemId);
        await prefs.setStringList(key, ids);
        debugPrint('[FloatWindow] Saved acknowledged reminder ID: $itemId');
      }
    } catch (e) {
      debugPrint('[FloatWindow] Failed to save acknowledged reminder: $e');
    }
  }

  static Future<void> _handleRemindLater() async {
    debugPrint('[FloatWindow] _handleRemindLater called');
    try {
      await windowManager.ensureInitialized();
      await windowManager.show();
      await windowManager.focus();

      Timer(Duration(milliseconds: FloatWindowConfig.snoozeDialogDelayMs), () {
        _showSnoozeDialog();
      });
    } catch (e) {
      debugPrint('[FloatWindow] Handle remind_later failed: $e');
    }
  }

  static void _showSnoozeDialog() {
    final context = appNavigatorKey.currentContext;
    if (context == null) {
      debugPrint('[FloatWindow] Context is null, cannot show dialog');
      return;
    }

    SnoozeDialog.show(context).then((minutes) async {
      if (minutes != null && minutes is int) {
        debugPrint('[FloatWindow] Schedule snooze: $minutes minutes');
        try {
          await IslandManager().sendStructuredPayload('island-1', {
            'state': 'snooze_reminder',
            'snoozeMinutes': minutes,
          });
          debugPrint(
              '[FloatWindow] Sent snooze_reminder payload: $minutes min');
        } catch (e) {
          debugPrint('[FloatWindow] Failed to send snooze_reminder: $e');
        }
      }
    });
  }

  // ── Action Processing ──────────────────────────────────────────────────

  static void _handleAction(String action, int secs) async {
    if (_processingAction) {
      debugPrint('[FloatWindow] action $action ignored: already processing');
      return;
    }
    _processingAction = true;
    final int myVersion = ++_actionVersion;

    debugPrint('[FloatWindow] _handleAction: action=$action, secs=$secs');

    if (isWorkbenchMounted) {
      try {
        final isFocused = await windowManager.isFocused();
        if (isFocused) {
          debugPrint('[FloatWindow] action $action skipped: workbench focused');
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

    // Clear state and update island
    await PomodoroService.clearRunState();
    clearFocus();
    await update(endMs: 0, isLocal: true);

    // Check version for staleness
    if (_actionVersion != myVersion) {
      debugPrint('[FloatWindow] action $action stale, skipping');
      _processingAction = false;
      return;
    }

    // Save record in background
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

  // ── Focus State Management ─────────────────────────────────────────────

  static void clearFocus() {
    _lastEndMs = 0;
    _lastTitle = '';
    _lastTags = const [];
    _lastIsLocal = true;
    _lastMode = 0;
  }

  // ── Main Update Method ─────────────────────────────────────────────────

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
    bool includeReminders = false,
  }) async {
    if (!Platform.isWindows) return;

    final prevEndMsSnapshot = _lastEndMs;

    // Update cached values
    if (endMs != null) {
      if (endMs == 0) {
        if (isLocal != null) {
          clearFocus();
        }
      } else {
        _lastEndMs = endMs;
        _lastTitle = title ?? _lastTitle;
        _lastTags = tags ?? _lastTags;
        _lastIsLocal = isLocal ?? _lastIsLocal;
        _lastMode = mode ?? _lastMode;
      }
    } else {
      if (_lastEndMs == 0) {
        _lastTitle = '';
        _lastTags = const [];
      }
    }

    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.reload();
    } catch (_) {}

    final style = prefs.getInt('float_window_style') ?? 0;

    if (style != 1) {
      if (Platform.isWindows) {
        try {
          await IslandManager().destroyCachedIsland('island-1');
        } catch (_) {}
      }
      return;
    }

    // Get slot data
    final defaultPriority = ['course', 'countdown', 'todo'];
    final priorityList =
        prefs.getStringList('island_slot_priority') ?? defaultPriority;

    String leftStr = '';
    String rightStr = '';
    IslandSlotData leftSlotData = const IslandSlotData.empty();
    IslandSlotData rightSlotData = const IslandSlotData.empty();

    List<IslandSlotData> validSlots = [];
    for (String pType in priorityList) {
      if (validSlots.length >= 2) break;
      final slotData = await IslandSlotProvider.getSlotData(pType,
          isLeft: validSlots.isEmpty);
      if (!slotData.isEmpty) {
        validSlots.add(slotData);
      }
    }

    if (validSlots.isNotEmpty) {
      leftSlotData = validSlots[0];
      leftStr = leftSlotData.display;
    }
    if (validSlots.length > 1) {
      rightSlotData = validSlots[1];
      rightStr = rightSlotData.display;
    }

    if (_lastEndMs == 0) {
      topBarLeft ??= leftStr;
      topBarRight ??= rightStr;
    }

    // Get reminders if requested
    if (reminderQueue == null && includeReminders) {
      reminderQueue = await IslandSlotProvider.getReminderQueue();
    }
    reminderQueue ??= <Map<String, String>>[];

    final detailSource = leftSlotData.isNotEmpty ? leftSlotData : rightSlotData;

    // Build payload
    final shouldForceReset =
        forceReset || (prevEndMsSnapshot == 0 && _lastEndMs > 0);

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
      'detail_type': detailSource.type,
      'detail_title': detailSource.detailTitle,
      'detail_subtitle': detailSource.detailSubtitle,
      'detail_location': detailSource.detailLocation,
      'detail_time': detailSource.detailTime,
      'detail_note': detailSource.detailNote,
    };

    // Deliver to island
    final int styleInt =
        (payload['style'] is int) ? payload['style'] as int : 0;
    if (Platform.isWindows && styleInt == 1) {
      try {
        final islandId = 'island-1';
        var winId = IslandManager().getCachedWindowId(islandId);

        if (winId == null) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - _lastIslandCreateAttemptMs <
              FloatWindowConfig.islandCreateCooldownMs) {
            winId = IslandManager().getCachedWindowId(islandId);
          } else {
            _lastIslandCreateAttemptMs = nowMs;
            winId = await IslandManager().createIsland(islandId);
          }
        }

        if (winId != null) {
          final dto = IslandPayload.fromMap(payload);
          final structured = _buildStructuredPayload(dto, prefs);

          final sent =
              await IslandManager().sendStructuredPayload(islandId, structured);
          if (sent) {
            try {
              debugPayload.value = null;
            } catch (_) {}
            return;
          }
        }
      } catch (e) {
        debugPrint('[FloatWindow] IslandManager delivery failed: $e');
      }
    }
  }

  static Map<String, dynamic> _buildStructuredPayload(
      IslandPayload p, SharedPreferences prefs) {
    final bool isFocusing = p.endMs > 0;
    final state = isFocusing ? 'focusing' : 'idle';

    final focusData = {
      'title': p.title,
      'timeLabel': (() {
        if (p.endMs > 0) {
          final now = DateTime.now().millisecondsSinceEpoch;
          int secs;
          if (p.mode == 1) {
            secs = (now - p.endMs) ~/ 1000;
          } else {
            secs = (p.endMs - now) ~/ 1000;
          }
          if (secs < 0) secs = 0;
          final mm = (secs ~/ 60).toString().padLeft(2, '0');
          final ss = (secs % 60).toString().padLeft(2, '0');
          return '$mm:$ss';
        }
        return '';
      })(),
      'isCountdown': p.mode != 1,
      'tags': p.tags,
      'syncMode': p.isLocal ? 'local' : 'remote',
      'endMs': p.endMs,
    };

    final reminderData = p.reminderQueue.isNotEmpty
        ? {
            'title': p.reminderQueue.first['text'] ?? '',
            'location': p.reminderQueue.first['type'] ?? '',
            'time': p.reminderQueue.first['timeLabel'] ?? '',
          }
        : {};

    final dashboardData = {
      'leftSlot': p.topBarLeft.isNotEmpty ? p.topBarLeft : p.left,
      'rightSlot': p.topBarRight.isNotEmpty ? p.topBarRight : p.right,
    };

    final bool transparentSupported =
        IslandManager().getTransparentSupport('island-1');

    return {
      'state': state,
      'theme': prefs.getString('theme') ?? 'system',
      'focusData': focusData,
      'reminderData': reminderData,
      'dashboardData': dashboardData,
      'transparentSupported': transparentSupported,
      'legacy': p.toMap(),
    };
  }

  // ── Position Management ────────────────────────────────────────────────

  static Future<void> resetPositions() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        try {
          await windowManager.ensureInitialized();
          await windowManager.center();
          try {
            final b = await windowManager.getBounds();
            final newTop = (b.top - 120).toInt();
            await windowManager.setBounds(
                Rect.fromLTWH(b.left, newTop.toDouble(), b.width, b.height));
          } catch (_) {}
          await windowManager.focus();
        } catch (_) {}
      }

      if (Platform.isWindows) {
        final islandId = 'island-1';
        final winId = IslandManager().getCachedWindowId(islandId);
        if (winId != null) {
          try {
            final w = FloatWindowConfig.defaultIslandWidth;
            final h = FloatWindowConfig.defaultIslandHeight;

            int left, top;
            try {
              final mb = await windowManager.getBounds();
              left = (mb.left + (mb.width - w) / 2).toInt();
              top = (mb.top + (mb.height - h) / 2).toInt();
            } catch (_) {
              left = 100;
              top = 100;
            }

            await IslandChannel.setWindowBounds(winId, {
              'left': left,
              'top': top,
              'width': w.toInt(),
              'height': h.toInt(),
            });

            debugPrint('[FloatWindow] Reset island position: $left, $top');
          } catch (e) {
            debugPrint('[FloatWindow] Failed to reset island position: $e');
          }
        }
      }

      try {
        await update(forceReset: true);
      } catch (_) {}
    } catch (_) {}
  }

  /// Trigger immediate reminder check on island
  static Future<void> triggerReminderCheck() async {
    debugPrint('[FloatWindow] triggerReminderCheck called');
    try {
      final islandId = 'island-1';
      final winId = IslandManager().getCachedWindowId(islandId);
      if (winId != null) {
        final dir = await getApplicationSupportDirectory();
        final filePath = '${dir.path}/island_action.json';
        final file = File(filePath);
        await file.writeAsString(jsonEncode({
          'action': 'check_reminder',
          'windowId': winId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
        debugPrint('[FloatWindow] Triggered island reminder check');
      } else {
        debugPrint('[FloatWindow] Island window not found');
      }
    } catch (e) {
      debugPrint('[FloatWindow] Failed to trigger reminder check: $e');
    }
  }
}
