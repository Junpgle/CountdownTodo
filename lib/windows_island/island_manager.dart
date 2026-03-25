import 'dart:async';
import 'package:flutter/foundation.dart';
import 'island_channel.dart';
import 'island_payload.dart';

class IslandManager {
  static final IslandManager _instance = IslandManager._internal();

  factory IslandManager() => _instance;

  IslandManager._internal();

  final Map<String, String> _windowIdCache = {}; // islandId -> windowId
  final Map<String, Future<String?>> _creating = {};

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

    // Start create and cache the future so concurrent callers wait
    final future = _doCreate(islandId);
    _creating[islandId] = future;
    final res = await future;
    _creating.remove(islandId);
    if (res != null) _windowIdCache[islandId] = res;
    return res;
  }

  Future<String?> _doCreate(String islandId) async {
    // Prepare an initial payload (empty) so island isn't blank
    final initial = IslandPayload.fromMap(null).toMap();
    final args = {
      'arguments': 'islandMain',
      'hiddenAtLaunch': false,
      'payload': initial,
    };
    try {
      debugPrint('[IslandManager] _doCreate calling IslandChannel.createWindow for $islandId');
      final windowId = await IslandChannel.createWindow(args);
      debugPrint('[IslandManager] _doCreate result for $islandId -> $windowId');
      // Small stabilization delay to allow the child engine to finish setup
      // before the host attempts to postWindowMessage. This reduces races
      // where createWindow returns but the child isn't ready to receive.
      if (windowId != null) {
        try {
          await Future.delayed(const Duration(milliseconds: 400));
        } catch (_) {}
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
    final Map<String, dynamic> map = payload.toMap();
    int attempts = 0;
    int delayMs = 50;
    while (attempts < 5) {
      attempts++;
      debugPrint('[IslandManager] sendPayload attempt $attempts -> windowId=$windowId');
      final ok = await IslandChannel.postMessage(windowId, map);
      if (ok) return true;
      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs = (delayMs * 2).clamp(50, 800);
    }
    // failed; clear cache to allow recreate
    debugPrint('[IslandManager] sendPayload failed for $islandId; clearing cache');
    _windowIdCache.remove(islandId);
    return false;
  }

  String? getCachedWindowId(String islandId) => _windowIdCache[islandId];

  Future<void> recreateIsland(String islandId) async {
    final old = _windowIdCache[islandId];
    if (old != null) {
      await IslandChannel.destroyWindow(old);
      _windowIdCache.remove(islandId);
    }
    await createIsland(islandId);
  }
}

