import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class IslandChannel {
  // Use the desktop_multi_window plugin channel name to create/post/close windows
  static const MethodChannel _dmw = MethodChannel('mixin.one/desktop_multi_window');

  static bool _handlerSet = false;

  // Map of windowId -> List<Completer<void>> waiting for ready signal
  static final Map<String, List<Completer<void>>> _readyCompleters = {};
  // FIFO queue for anonymous ready waiters when windowId isn't provided
  static final List<Completer<void>> _anonReadyQueue = [];
  // Set of windowIds that have already signaled ready (sticky)
  static final Set<String> _readySet = {};
  
  // Stream for incoming onAction events from child windows
  static final StreamController<Map<String, dynamic>> _actionController = StreamController.broadcast();

  static Stream<Map<String, dynamic>> get actionStream => _actionController.stream;
  static Timer? _actionFileTimer;

  static void ensureInitialized() {
    if (_handlerSet) return;
    _handlerSet = true;

    // File IPC Polling: Check every 200ms if sub-window has written an action file.
    // This bypasses Flutter's engine/isolate isolation for custom method calls.
    _actionFileTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/island_action.json');
        if (await file.exists()) {
          final content = await file.readAsString();
          // Delete immediately to prevent double-processing
          try { await file.delete(); } catch (_) {}
          
          final map = Map<String, dynamic>.from(jsonDecode(content));
          final action = map['action']?.toString();
          debugPrint('[IslandChannel] file IPC received: $action');

          if (action == 'ready') {
            final winId = map['windowId']?.toString();
            if (winId != null) {
              if (_readyCompleters.containsKey(winId)) {
                final list = _readyCompleters.remove(winId);
                for (var c in list!) {
                  if (!c.isCompleted) c.complete();
                }
                debugPrint('[IslandChannel] completed ${list.length} ready waiters for windowId=$winId');
              } else {
                _readySet.add(winId);
                debugPrint('[IslandChannel] recorded sticky ready for windowId=$winId');
              }
            } else if (_anonReadyQueue.isNotEmpty) {
              _anonReadyQueue.removeAt(0).complete();
              debugPrint('[IslandChannel] completed anonymous ready waiter');
            }
          } else if (action != null) {
            debugPrint('[IslandChannel] forwarding to actionStream: $map');
            _actionController.add(map);
          }
        }
      } catch (e) {
        debugPrint('[IslandChannel] file IPC error: $e');
      }
    });

    // Original controller-based handler for window-level actions (dragging, resizing)
    // This handler is specific to the current window's controller.
    Future.microtask(() async {
      try {
        final controller = await WindowController.fromCurrentEngine();
        controller.setWindowMethodHandler((call) async {
          try {
            debugPrint('[IslandChannel] incoming controller method: ${call.method} args=${call.arguments}');
            if (call.method == 'onAction') {
              final args = call.arguments;
              debugPrint('[IslandChannel] onAction received (legacy/window): $args');
              if (args is Map) {
                try {
                  final map = Map<String, dynamic>.from(args);
                  if (map.isNotEmpty) {
                    _actionController.add(map);
                  }
                } catch (e) {}
              }
            } else if (call.method == 'postWindowMessage') {
              // Forward host-received postWindowMessage if relevant
              debugPrint('[IslandChannel] host received postWindowMessage: ${call.arguments}');
            }
          } catch (e) {
            debugPrint('[IslandChannel] incoming controller handler error: $e');
          }
          return null;
        });
      } catch (e) {
        debugPrint('[IslandChannel] failed to attach WindowController handler: $e');
      }
    });
  }

  /// Wait for a child window to signal ready.
  static Future<bool> waitForReady(String? windowId, {Duration timeout = const Duration(milliseconds: 2000)}) async {
    ensureInitialized();
    if (windowId != null && _readySet.contains(windowId)) {
      _readySet.remove(windowId);
      return true;
    }
    final completer = Completer<void>();
    if (windowId != null && windowId.isNotEmpty) {
      _readyCompleters.putIfAbsent(windowId, () => []).add(completer);
    } else {
      _anonReadyQueue.add(completer);
    }
    try {
      await completer.future.timeout(timeout);
      return true;
    } catch (_) {
      if (windowId != null && _readyCompleters.containsKey(windowId)) {
        _readyCompleters[windowId]?.remove(completer);
        if (_readyCompleters[windowId]!.isEmpty) _readyCompleters.remove(windowId);
      } else if (windowId == null) {
        _anonReadyQueue.remove(completer);
      }
      return false;
    }
  }

  /// Record ready status (idempotent helper)
  static void recordReady(String windowId) {
    try {
      if (_readyCompleters.containsKey(windowId)) {
        final list = _readyCompleters.remove(windowId);
        for (var c in list!) {
          if (!c.isCompleted) c.complete();
        }
      } else {
        _readySet.add(windowId);
      }
    } catch (_) {}
  }

  static Future<String?> createWindow(Map<String, dynamic> args) async {
    try {
      debugPrint('[IslandChannel] createWindow args: $args');
      final res = await _dmw.invokeMethod('createWindow', args);
      if (res is String && res.isNotEmpty) return res;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setWindowBounds(String windowId, Map<String, dynamic> bounds) async {
    try {
      final res = await _dmw.invokeMethod('setWindowBounds', {'windowId': windowId, 'bounds': bounds});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> showWindow(String windowId) async {
    try {
      final res = await _dmw.invokeMethod('showWindow', {'windowId': windowId});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hideWindow(String windowId) async {
    try {
      final res = await _dmw.invokeMethod('window_hide', {'windowId': windowId});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setWindowTransparent(String windowId, bool transparent) async {
    try {
      final res = await _dmw.invokeMethod('setWindowTransparent', {'windowId': windowId, 'transparent': transparent});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> postMessage(String windowId, Map<String, dynamic> payload) async {
    try {
      final res = await _dmw.invokeMethod('postWindowMessage', {'windowId': windowId, 'payload': payload});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<String>> getAllWindowIds() async {
    try {
      final res = await _dmw.invokeMethod('getAllWindows');
      if (res is List) {
        return res.map((e) {
          if (e is Map) {
            return e['windowId']?.toString() ?? '';
          }
          return e.toString();
        }).where((id) => id.isNotEmpty).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<bool> destroyWindow(String windowId) async {
    // First hide the window for immediate visual feedback
    try {
      await _dmw.invokeMethod('window_hide', {'windowId': windowId});
    } catch (_) {}
    // Then close/remove from the manager for actual cleanup
    try {
      final res = await _dmw.invokeMethod('closeWindow', {'windowId': windowId});
      return res == true;
    } catch (_) {
      return false;
    }
  }
}
