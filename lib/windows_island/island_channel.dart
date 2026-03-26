import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

class IslandChannel {
  // Use the desktop_multi_window plugin channel name to create/post/close windows
  static const MethodChannel _dmw = MethodChannel('mixin.one/desktop_multi_window');
  
  // Custom channel for reliable island-to-host business actions
  static const MethodChannel _actionChannel = MethodChannel('mixin.one/island_actions');

  static bool _handlerSet = false;

  // Map of windowId -> Completer<void> waiting for ready signal
  static final Map<String, Completer<void>> _readyCompleters = {};
  // FIFO queue for anonymous ready waiters when windowId isn't provided
  static final List<Completer<void>> _anonReadyQueue = [];
  // Set of windowIds that have already signaled ready (sticky)
  static final Set<String> _readySet = {};
  
  // Stream for incoming onAction events from child windows
  static final StreamController<Map<String, dynamic>> _actionController = StreamController.broadcast();

  static Stream<Map<String, dynamic>> get actionStream => _actionController.stream;

  static void ensureInitialized() {
    if (_handlerSet) return;
    _handlerSet = true;

    // 1) Specialized channel handler for reliable business actions (finish, abandon, ready)
    _actionChannel.setMethodCallHandler((call) async {
      try {
        debugPrint('[IslandChannel] actionChannel received: ${call.method} args=${call.arguments}');
        if (call.method == 'onAction') {
          final args = call.arguments;
          if (args is Map && args['action'] == 'ready') {
            final winId = args['windowId']?.toString();
            if (winId != null) {
              if (_readyCompleters.containsKey(winId)) {
                _readyCompleters.remove(winId)?.complete();
                debugPrint('[IslandChannel] completed ready for windowId=$winId');
              } else {
                _readySet.add(winId);
                debugPrint('[IslandChannel] recorded sticky ready for windowId=$winId');
              }
            } else if (_anonReadyQueue.isNotEmpty) {
              _anonReadyQueue.removeAt(0).complete();
              debugPrint('[IslandChannel] completed anonymous ready waiter');
            }
          } else if (args is Map) {
            try {
              final map = Map<String, dynamic>.from(args);
              if (map.isNotEmpty) {
                debugPrint('[IslandChannel] forwarding to actionStream: $map');
                _actionController.add(map);
              }
            } catch (e) {
              debugPrint('[IslandChannel] failed to forward action: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('[IslandChannel] actionChannel handler error: $e');
      }
      return null;
    });

    // 2) Original controller-based handler for window-level actions (dragging, resizing)
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
      _readyCompleters[windowId] = completer;
    } else {
      _anonReadyQueue.add(completer);
    }
    try {
      await completer.future.timeout(timeout);
      return true;
    } catch (_) {
      if (windowId != null) _readyCompleters.remove(windowId);
      else _anonReadyQueue.remove(completer);
      return false;
    }
  }

  /// Record ready status (idempotent helper)
  static void recordReady(String windowId) {
    try {
      if (_readyCompleters.containsKey(windowId)) {
        _readyCompleters.remove(windowId)?.complete();
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

  static Future<bool> destroyWindow(String windowId) async {
    try {
      final res = await _dmw.invokeMethod('closeWindow', {'windowId': windowId});
      return res == true;
    } catch (_) {
      return false;
    }
  }
}
