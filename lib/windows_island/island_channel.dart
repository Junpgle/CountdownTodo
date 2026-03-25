import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class IslandChannel {
  // Use the desktop_multi_window plugin channel name to create/post/close windows
  static const MethodChannel _dmw = MethodChannel('mixin.one/desktop_multi_window');

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


