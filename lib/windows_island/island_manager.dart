import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'island_channel.dart';
import 'island_payload.dart';
import '../storage_service.dart';
import 'package:window_manager/window_manager.dart';

class IslandManager {
  static final IslandManager _instance = IslandManager._internal();

  factory IslandManager() => _instance;

  IslandManager._internal();

  final Map<String, String> _windowIdCache = {}; // islandId -> windowId
  final Map<String, Future<String?>> _creating = {};
  // Cache whether the host supports transparent windows for each islandId
  final Map<String, bool> _transparentSupport = {};

  // ── Persistent window ID file ──────────────────────────────────────────
  // The window ID is persisted to a file so that even after an app restart,
  // we can find and close orphaned island windows.
  static Future<File> _windowIdFile(String islandId) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/island_wid_$islandId.txt');
  }

  Future<void> _persistWindowId(String islandId, String windowId) async {
    try {
      final f = await _windowIdFile(islandId);
      await f.writeAsString(windowId);
    } catch (_) {}
  }

  Future<String?> _loadPersistedWindowId(String islandId) async {
    try {
      final f = await _windowIdFile(islandId);
      if (await f.exists()) {
        final s = (await f.readAsString()).trim();
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _clearPersistedWindowId(String islandId) async {
    try {
      final f = await _windowIdFile(islandId);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ── Public API ─────────────────────────────────────────────────────────

  Future<String?> createIsland(String islandId) async {
    if (kIsWeb) return null;

    // Return cached id if present
    final cached = _windowIdCache[islandId];
    if (cached != null) return cached;

    // If a create is already in progress for this id, await it
    if (_creating.containsKey(islandId)) {
      try {
        return await _creating[islandId];
      } catch (_) {
        return null;
      }
    }

    // Before creating a new window, destroy any orphaned window from a
    // previous session (window ID persisted to file but lost from memory).
    try {
      final orphanId = await _loadPersistedWindowId(islandId);
      if (orphanId != null) {
        debugPrint(
            '[IslandManager] destroying orphaned window $orphanId before creating new island');
        await IslandChannel.destroyWindow(orphanId);
        await _clearPersistedWindowId(islandId);
      }
    } catch (_) {}

    // Start create and cache the future so concurrent callers wait
    final future = _doCreate(islandId);
    _creating[islandId] = future;
    try {
      final res = await future;
      if (res != null) {
        _windowIdCache[islandId] = res;
        await _persistWindowId(islandId, res);
      }
      return res;
    } finally {
      _creating.remove(islandId);
    }
  }

  Future<String?> _doCreate(String islandId) async {
    final initialLegacy = IslandPayload.fromMap(null).toMap();
    final initialStructured = {
      'state': 'idle',
      'theme': 'system',
      'focusData': {
        'title': '',
        'timeLabel': '',
        'isCountdown': true,
        'tags': [],
        'syncMode': 'local'
      },
      'reminderData': {},
      'dashboardData': {'leftSlot': '', 'rightSlot': ''},
      'transparentSupported': false,
      'legacy': initialLegacy,
    };

    final args = {
      'arguments': 'islandMain',
      'hiddenAtLaunch': false,
      'alwaysOnTop': true,
      'skipTaskbar': true,
      'transparent': true,
      'payload': initialStructured,
    };
    try {
      final bounds = await StorageService.getIslandBounds(islandId);
      if (bounds != null && bounds.isNotEmpty) {
        args['initialBounds'] = bounds;
      }
    } catch (_) {}
    // If there are no persisted bounds, center relative to main window
    try {
      if (args['initialBounds'] == null) {
        await windowManager.ensureInitialized();
        try {
          final mainBounds = await windowManager.getBounds();
          const double defaultW = 160.0;
          const double defaultH = 56.0;
          final left =
              (mainBounds.left + (mainBounds.width - defaultW) / 2).toInt();
          final top =
              (mainBounds.top + (mainBounds.height - defaultH) / 2).toInt();
          args['initialBounds'] = {
            'left': left,
            'top': top,
            'width': defaultW,
            'height': defaultH,
          };
          debugPrint(
              '[IslandManager] applying computed initialBounds for $islandId: ${args['initialBounds']}');
        } catch (_) {}
      }
    } catch (_) {}
    if (args['initialBounds'] == null) {
      args['initialBounds'] = {
        'left': 100,
        'top': 100,
        'width': 160.0,
        'height': 56.0
      };
      debugPrint(
          '[IslandManager] applied fallback initialBounds for $islandId: ${args['initialBounds']}');
    }
    try {
      debugPrint(
          '[IslandManager] _doCreate calling IslandChannel.createWindow for $islandId');
      final windowId = await IslandChannel.createWindow(args);
      debugPrint('[IslandManager] _doCreate result for $islandId -> $windowId');
      if (windowId != null) {
        try {
          await IslandChannel.postMessage(windowId, initialStructured);
        } catch (_) {}
        try {
          final ib = args['initialBounds'] as Map<String, dynamic>?;
          if (ib != null) {
            debugPrint('[IslandManager] 调用 setWindowBounds: $ib');
            final boundsResult =
                await IslandChannel.setWindowBounds(windowId, ib)
                    .catchError((e) {
              debugPrint('[IslandManager] setWindowBounds error: $e');
              return false;
            });
            debugPrint('[IslandManager] setWindowBounds result: $boundsResult');

            await IslandChannel.showWindow(windowId).catchError((_) => false);
            try {
              final got =
                  await IslandChannel.setWindowTransparent(windowId, true)
                      .catchError((_) => false);
              _transparentSupport[islandId] = got == true;
              debugPrint('[IslandManager] setWindowTransparent 结果: $got');
              if (!got) {
                debugPrint('[IslandManager] 插件透明设置失败，依赖 Win32 后备方案');
              }
            } catch (_) {
              _transparentSupport[islandId] = false;
            }
            debugPrint(
                '[IslandManager] applied initialBounds, showed window and requested transparency for $windowId');
          }
        } catch (_) {}
        try {
          await Future.delayed(const Duration(milliseconds: 400));
        } catch (_) {}
        try {
          final ok = await IslandChannel.waitForReady(windowId,
              timeout: const Duration(milliseconds: 1200));
          debugPrint('[IslandManager] waitForReady result for $windowId: $ok');
          if (!ok) {
            debugPrint(
                '[IslandManager] waitForReady timed out for $windowId; sending handshake ping');
            await IslandChannel.postMessage(windowId, {'handshake': 'ping'});
            final completer = Completer<bool>();
            final sub = IslandChannel.actionStream.listen((event) {
              try {
                if (event['action'] == 'handshake_pong' &&
                    event['windowId'] == windowId) {
                  completer.complete(true);
                }
              } catch (_) {}
            });
            try {
              final got = await completer.future.timeout(
                  const Duration(milliseconds: 1000),
                  onTimeout: () => false);
              debugPrint(
                  '[IslandManager] handshake_pong result for $windowId: $got');
            } catch (_) {}
            try {
              await sub.cancel();
            } catch (_) {}
          }
        } catch (e) {
          debugPrint(
              '[IslandManager] waitForReady exception for $windowId: $e');
        }
      }
      return windowId;
    } catch (_) {
      debugPrint('[IslandManager] _doCreate exception for $islandId: $_');
      return null;
    }
  }

  Future<bool> sendPayload(String islandId, IslandPayload payload) async {
    final windowId = _windowIdCache[islandId];
    if (windowId == null) return false;
    try {
      final ready = await IslandChannel.waitForReady(windowId,
          timeout: const Duration(milliseconds: 600));
      debugPrint(
          '[IslandManager] pre-send waitForReady for $windowId -> $ready');
    } catch (_) {}
    int attempts = 0;
    int delayMs = 50;
    while (attempts < 5) {
      attempts++;
      debugPrint(
          '[IslandManager] sendPayload attempt $attempts -> windowId=$windowId');
      final ok = await IslandChannel.postMessage(windowId, payload.toMap());
      if (ok) return true;
      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs = (delayMs * 2).clamp(50, 800);
    }
    debugPrint(
        '[IslandManager] sendPayload failed for $islandId (windowId=$windowId)');
    return false;
  }

  String? getCachedWindowId(String islandId) => _windowIdCache[islandId];

  bool getTransparentSupport(String islandId) =>
      _transparentSupport[islandId] ?? false;

  Future<void> recreateIsland(String islandId) async {
    await destroyCachedIsland(islandId);
    // avoid immediate recreate loops
    _lastRecreateMs ??= {};
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastRecreateMs![islandId] ?? 0;
    if (now - last < 1200) {
      debugPrint(
          '[IslandManager] recreateIsland suppressed due to recent recreate (${now - last}ms)');
      return;
    }
    _lastRecreateMs![islandId] = now;
    await createIsland(islandId);
  }

  /// Destroy the island window — checks both in-memory cache and persisted file.
  Future<void> destroyCachedIsland(String islandId) async {
    // 1. Close tracked window from in-memory cache
    final old = _windowIdCache[islandId];
    if (old != null) {
      try {
        debugPrint(
            '[IslandManager] destroying tracked island $islandId (windowId=$old)');
        await IslandChannel.destroyWindow(old);
      } catch (_) {}
      _windowIdCache.remove(islandId);
    }

    // 2. Also try to close any orphaned window from persisted file
    try {
      final persisted = await _loadPersistedWindowId(islandId);
      if (persisted != null && persisted != old) {
        debugPrint(
            '[IslandManager] destroying persisted orphan window $persisted');
        await IslandChannel.destroyWindow(persisted);
      }
    } catch (_) {}

    await _clearPersistedWindowId(islandId);
    _transparentSupport.remove(islandId);
  }

  Map<String, int>? _lastRecreateMs;

  /// Send a structured payload (Map) to island windowId. Returns true on success.
  Future<bool> sendStructuredPayload(
      String islandId, Map<String, dynamic> payload) async {
    final windowId = _windowIdCache[islandId];
    if (windowId == null) return false;
    try {
      await IslandChannel.waitForReady(windowId,
          timeout: const Duration(milliseconds: 600));
    } catch (_) {}
    final ok = await IslandChannel.postMessage(windowId, payload);
    if (!ok) {
      debugPrint(
          '[IslandManager] sendStructuredPayload failed for $windowId; NOT clearing cache to avoid duplication');
    }
    return ok;
  }
}
