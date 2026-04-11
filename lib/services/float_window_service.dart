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
import '../windows_island/island_manager.dart';
import '../windows_island/island_channel.dart';
import 'clipboard_service.dart';
import 'snooze_dialog.dart';
import 'island_data_provider.dart';

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
  static int _lastAccumulatedMs = 0;
  static int _lastPauseStartMs = 0;

  // Island creation throttling
  static int _lastIslandCreateAttemptMs = 0;
  static Future<String?>? _creatingIsland; // 互斥锁, 防止并发创建

  // Data provider with caching
  static final _dataProvider = IslandDataProvider();

  /// Initialize the service
  static Future<void> init() async {
    if (!Platform.isWindows) return;
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

      var winId = IslandManager().getCachedWindowId('island-1');
      debugPrint('[FloatWindow] island-1 windowId: $winId');

      if (winId == null) {
        debugPrint('[FloatWindow] Island not found, attempting to create');
        winId = await IslandManager().createIsland('island-1');
        debugPrint('[FloatWindow] Created island, windowId: $winId');
        if (winId == null) {
          debugPrint('[FloatWindow] Failed to create island');
          return;
        }
      }

      final sent =
          await IslandManager().sendStructuredPayload('island-1', payload);
      debugPrint(
          '[FloatWindow] Sent copied_link payload: $displayUrl, success: $sent');
    } catch (e, stackTrace) {
      debugPrint(
          '[FloatWindow] Failed to show copied link island: $e\n$stackTrace');
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
        case 'link_opened':
          // 链接已打开，刷新岛的状态恢复到之前的数据
          debugPrint('[FloatWindow] link_opened, refreshing island state');
          _refreshIslandAfterLinkOpened();
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

  /// 刷新岛的状态（在打开链接后恢复）
  static Future<void> _refreshIslandAfterLinkOpened() async {
    try {
      // 强制刷新槽位缓存
      _dataProvider.invalidateSlotCache();
      // 重置上次复制的URL，允许再次检测相同URL
      _lastCopiedUrl = null;

      // Add delay to let the island restore its state first
      // before sending a refresh payload
      await Future.delayed(Duration(milliseconds: 500));

      // 使用当前状态重新更新岛
      await update(forceReset: true);
      debugPrint('[FloatWindow] Island state refreshed after link opened');
    } catch (e) {
      debugPrint('[FloatWindow] Failed to refresh island after link: $e');
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
    _lastAccumulatedMs = 0;
    _lastPauseStartMs = 0;
    _dataProvider.resetTrackingState();
  }

  // ── Main Update Method (Simplified) ────────────────────────────────────

  /// Update the island with current state.
  /// This is the main entry point for all island updates.
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
    bool isPaused = false,
    int? accumulatedMs,
    int? pauseStartMs,
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
        _lastAccumulatedMs = accumulatedMs ?? _lastAccumulatedMs;
        _lastPauseStartMs = pauseStartMs ?? _lastPauseStartMs;
      }
    } else {
      if (_lastEndMs == 0) {
        _lastTitle = '';
        _lastTags = const [];
        _lastAccumulatedMs = 0;
        _lastPauseStartMs = 0;
      }
    }

    // Check if island is enabled
    final style = await _dataProvider.getStyle();
    debugPrint('[FloatWindow] update: style=$style, forceReset=$forceReset');
    if (style != 1) {
      debugPrint('[FloatWindow] style != 1, destroying island');
      try {
        await IslandManager().destroyCachedIsland('island-1');
      } catch (_) {}
      return;
    }

    // Get transparent support
    final bool transparentSupported =
        IslandManager().getTransparentSupport('island-1');

    // Build payload using data provider
    final shouldForceReset =
        forceReset || (prevEndMsSnapshot == 0 && _lastEndMs > 0);

    final structured = await _dataProvider.buildPayload(
      endMs: _lastEndMs,
      title: _lastTitle,
      tags: _lastTags,
      isLocal: _lastIsLocal,
      mode: _lastMode,
      forceReset: shouldForceReset,
      topBarLeft: topBarLeft,
      topBarRight: topBarRight,
      reminderQueue: reminderQueue,
      includeReminders: includeReminders,
      transparentSupported: transparentSupported,
      isPaused: isPaused,
      accumulatedMs: _lastAccumulatedMs,
      pauseStartMs: _lastPauseStartMs,
    );

    // If null, no update needed
    if (structured == null) {
      debugPrint('[FloatWindow] No update needed');
      return;
    }

    // Deliver to island
    await _deliverToIsland(structured);
  }

  static int _lastDeliveryMs = 0;

  /// Deliver payload to island window
  static Future<void> _deliverToIsland(Map<String, dynamic> structured) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Throttle deliveries to at most once every 100ms to avoid clogging the channel
    if (now - _lastDeliveryMs < 100 && structured['state'] == 'focusing') {
       return;
    }
    _lastDeliveryMs = now;
    try {
      final islandId = 'island-1';
      var winId = IslandManager().getCachedWindowId(islandId);
      debugPrint(
          '[FloatWindow] _deliverToIsland: winId=$winId, state=${structured['state']}');

      if (winId == null) {
        // 互斥锁: 等待已在进行的创建, 或自己发起创建
        if (_creatingIsland != null) {
          debugPrint(
              '[FloatWindow] Waiting for in-progress island creation...');
          winId = await _creatingIsland;
        } else {
          debugPrint('[FloatWindow] Creating island: $islandId');
          final future = IslandManager().createIsland(islandId);
          _creatingIsland = future;
          try {
            winId = await future;
          } finally {
            _creatingIsland = null;
          }
          debugPrint('[FloatWindow] Created island: winId=$winId');
        }
      }

      if (winId != null) {
        final sent =
            await IslandManager().sendStructuredPayload(islandId, structured);
        debugPrint('[FloatWindow] sendStructuredPayload result: $sent');
        if (sent) {
          debugPrint(
              '[FloatWindow] Sent payload to island: state=${structured['state']}');
          try {
            debugPayload.value = null;
          } catch (_) {}
        }
      } else {
        debugPrint(
            '[FloatWindow] Cannot deliver: winId is null after all attempts');
      }
    } catch (e, stackTrace) {
      debugPrint('[FloatWindow] Island delivery failed: $e\n$stackTrace');
    }
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

  /// Invalidate data cache (call when significant data changes)
  static void invalidateCache() {
    _dataProvider.invalidateCache();
  }

  /// Invalidate only slot cache
  static void invalidateSlotCache() {
    _dataProvider.invalidateSlotCache();
  }

  /// Get debug info
  static Map<String, dynamic> getDebugInfo() {
    return _dataProvider.getDebugInfo();
  }
}
