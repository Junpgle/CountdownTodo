import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

class IslandChannel {
  // Use the desktop_multi_window plugin channel name to create/post/close windows
  static const MethodChannel _dmw = MethodChannel('mixin.one/desktop_multi_window');
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
	Future.microtask(() async {
	  try {
		final controller = await WindowController.fromCurrentEngine();
		controller.setWindowMethodHandler((call) async {
	      try {
			debugPrint('[IslandChannel] incoming controller method: ${call.method} args=${call.arguments}');
			final args = call.arguments;
		if (call.method == 'onAction') {
		  if (args is Map && args['action'] == 'ready') {
			// Try to extract windowId if present
			String? winId;
			if (args['windowId'] is String) winId = args['windowId'] as String;
			if (winId != null) {
			  if (_readyCompleters.containsKey(winId)) {
				_readyCompleters.remove(winId)?.complete();
				debugPrint('[IslandChannel] completed ready for windowId=$winId');
			  } else {
				// Record sticky ready so future waiters succeed
				_readySet.add(winId);
				debugPrint('[IslandChannel] recorded sticky ready for windowId=$winId');
			  }
			} else if (_anonReadyQueue.isNotEmpty) {
			  _anonReadyQueue.removeAt(0).complete();
			  debugPrint('[IslandChannel] completed anonymous ready waiter');
			}
		  } else if (args is Map) {
			// Non-ready onAction events (user interactions) -> forward to stream
			try {
			  final map = Map<String, dynamic>.from(args);
			  if (map.isNotEmpty) {
				_actionController.add({
				  ...map,
				  'windowId': map['windowId'], 
				  'action': map['action'],
				});
				debugPrint('[IslandChannel] forwarded action from window: $map');
			  }
			} catch (e) {
			  debugPrint('[IslandChannel] failed to forward action: $e');
			}
		  }
		} else if (call.method == 'postWindowMessage') {
		  // Forward host-received postWindowMessage to any listeners if needed.
		  // For now just log.
		  debugPrint('[IslandChannel] host received postWindowMessage: $args');
		}
		  } catch (e) {
			debugPrint('[IslandChannel] incoming handler error: $e');
		  }
		  return null;
		});
	  } catch (e) {
		debugPrint('[IslandChannel] failed to attach WindowController handler: $e');
	  }
	});
  }

  /// Wait for a child window to signal ready. If windowId is null, wait on
  /// an anonymous FIFO slot.
  static Future<bool> waitForReady(String? windowId, {Duration timeout = const Duration(milliseconds: 2000)}) async {
	ensureInitialized();
	// If windowId already recorded as ready (sticky), return immediately
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
	  // cleanup if still present
	  if (windowId != null) _readyCompleters.remove(windowId);
	  else _anonReadyQueue.remove(completer);
	  return false;
	}
  }

  /// Record that a windowId has signaled ready. Completes any pending waiter
  /// or marks it sticky so future waiters succeed.
  static void recordReady(String windowId) {
	try {
	  if (_readyCompleters.containsKey(windowId)) {
		_readyCompleters.remove(windowId)?.complete();
		debugPrint('[IslandChannel] recordReady completed pending for $windowId');
	  } else {
		_readySet.add(windowId);
		debugPrint('[IslandChannel] recordReady recorded sticky for $windowId');
	  }
	} catch (e) {
	  debugPrint('[IslandChannel] recordReady error: $e');
	}
  }

  /// Create a new window using desktop_multi_window.
  /// args: a Map of arguments; we typically pass {'arguments': 'islandMain', 'payload': {...}, 'hiddenAtLaunch': false}
  static Future<String?> createWindow(Map<String, dynamic> args) async {
	try {
	  debugPrint('[IslandChannel] createWindow args: $args');
	  final res = await _dmw.invokeMethod('createWindow', args);
	  debugPrint('[IslandChannel] createWindow result: $res');
	  if (res is String && res.isNotEmpty) return res;
	  return null;
	} on MissingPluginException catch (_) {
	  debugPrint('[IslandChannel] createWindow MissingPluginException');
	  return null;
	} catch (_) {
	  debugPrint('[IslandChannel] createWindow exception: $_');
	  return null;
	}
  }

  /// Best-effort: set bounds for an existing window using the host plugin.
  static Future<bool> setWindowBounds(String windowId, Map<String, dynamic> bounds) async {
	try {
	  debugPrint('[IslandChannel] setWindowBounds -> windowId=$windowId bounds=$bounds');
	  final res = await _dmw.invokeMethod('setWindowBounds', {'windowId': windowId, 'bounds': bounds});
	  debugPrint('[IslandChannel] setWindowBounds result: $res');
	  return res == true;
	} catch (e) {
	  debugPrint('[IslandChannel] setWindowBounds exception: $e');
	  return false;
	}
  }

  /// Best-effort: show a window that was created hidden.
  static Future<bool> showWindow(String windowId) async {
	try {
	  debugPrint('[IslandChannel] showWindow -> windowId=$windowId');
	  final res = await _dmw.invokeMethod('showWindow', {'windowId': windowId});
	  debugPrint('[IslandChannel] showWindow result: $res');
	  return res == true;
	} catch (e) {
	  debugPrint('[IslandChannel] showWindow exception: $e');
	  return false;
	}
  }

  /// Best-effort: request host to set window transparency (if supported).
  static Future<bool> setWindowTransparent(String windowId, bool transparent) async {
	try {
	  debugPrint('[IslandChannel] setWindowTransparent -> windowId=$windowId transparent=$transparent');
	  final res = await _dmw.invokeMethod('setWindowTransparent', {'windowId': windowId, 'transparent': transparent});
	  debugPrint('[IslandChannel] setWindowTransparent result: $res');
	  return res == true;
	} catch (e) {
	  debugPrint('[IslandChannel] setWindowTransparent exception: $e');
	  return false;
	}
  }

  /// Post a message (Map payload) to an existing window id
  static Future<bool> postMessage(String windowId, Map<String, dynamic> payload) async {
	try {
	  debugPrint('[IslandChannel] postMessage -> windowId=$windowId payload=$payload');
	  final res = await _dmw.invokeMethod('postWindowMessage', {'windowId': windowId, 'payload': payload});
	  debugPrint('[IslandChannel] postMessage result: $res');
	  return res == true;
	} on MissingPluginException catch (_) {
	  debugPrint('[IslandChannel] postMessage MissingPluginException');
	  return false;
	} catch (_) {
	  debugPrint('[IslandChannel] postMessage exception: $_');
	  return false;
	}
  }

  /// Close/destroy a window by id
  static Future<bool> destroyWindow(String windowId) async {
	try {
	  debugPrint('[IslandChannel] destroyWindow -> windowId=$windowId');
	  final res = await _dmw.invokeMethod('closeWindow', {'windowId': windowId});
	  debugPrint('[IslandChannel] destroyWindow result: $res');
	  return res == true;
	} on MissingPluginException catch (_) {
	  debugPrint('[IslandChannel] destroyWindow MissingPluginException');
	  return false;
	} catch (_) {
	  debugPrint('[IslandChannel] destroyWindow exception: $_');
	  return false;
	}
  }
}


