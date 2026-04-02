import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'island_slot_provider.dart';
import '../windows_island/island_payload.dart';

/// Cache entry for island data
class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;

  _CacheEntry(this.data) : timestamp = DateTime.now();

  bool isValid(Duration maxAge) {
    return DateTime.now().difference(timestamp) < maxAge;
  }
}

/// Centralized data provider for island window.
/// Manages caching and aggregates data from multiple sources.
class IslandDataProvider {
  IslandDataProvider._();

  static final IslandDataProvider _instance = IslandDataProvider._internal();
  factory IslandDataProvider() => _instance;
  IslandDataProvider._internal();

  // ── Cache Configuration ────────────────────────────────────────────────

  /// Slot data cache duration
  static const Duration slotCacheDuration = Duration(seconds: 30);

  /// Settings cache duration
  static const Duration settingsCacheDuration = Duration(minutes: 5);

  // ── Cached State ───────────────────────────────────────────────────────

  _CacheEntry<Map<String, IslandSlotData>>? _slotCache;
  _CacheEntry<int>? _styleCache;
  _CacheEntry<List<String>>? _priorityCache;
  _CacheEntry<String>? _themeCache;

  // ── Last Sent State ────────────────────────────────────────────────────

  /// Track last sent payload to detect actual changes
  Map<String, dynamic>? _lastSentPayload;
  int _lastSentEndMs = 0;
  String _lastSentState = '';

  // ── Public API ─────────────────────────────────────────────────────────

  /// Get island style (0=classic, 1=island, 2=disabled)
  Future<int> getStyle() async {
    if (_styleCache != null && _styleCache!.isValid(settingsCacheDuration)) {
      return _styleCache!.data;
    }
    final prefs = await SharedPreferences.getInstance();
    final style = prefs.getInt('float_window_style') ?? 0;
    _styleCache = _CacheEntry(style);
    return style;
  }

  /// Get slot priority list
  Future<List<String>> getSlotPriority() async {
    if (_priorityCache != null &&
        _priorityCache!.isValid(settingsCacheDuration)) {
      return _priorityCache!.data;
    }
    final prefs = await SharedPreferences.getInstance();
    final priority = prefs.getStringList('island_slot_priority') ??
        ['course', 'countdown', 'todo', 'focus', 'date', 'weekday'];
    _priorityCache = _CacheEntry(priority);
    return priority;
  }

  /// Get theme mode
  Future<String> getTheme() async {
    if (_themeCache != null && _themeCache!.isValid(settingsCacheDuration)) {
      return _themeCache!.data;
    }
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString('theme') ?? 'system';
    _themeCache = _CacheEntry(theme);
    return theme;
  }

  /// Get slot data with caching
  Future<Map<String, IslandSlotData>> getSlotData(
      {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _slotCache != null &&
        _slotCache!.isValid(slotCacheDuration)) {
      return _slotCache!.data;
    }

    final priority = await getSlotPriority();
    final Map<String, IslandSlotData> slots = {};

    for (final type in priority) {
      // Fetch as left to check for content. We'll refine for right slot in buildPayload.
      final data = await IslandSlotProvider.getSlotData(type, isLeft: true);
      if (data.isNotEmpty) {
        slots[type] = data;
      }
    }

    _slotCache = _CacheEntry(slots);
    return slots;
  }

  /// Build complete island payload
  /// Returns null if no update is needed
  Future<Map<String, dynamic>?> buildPayload({
    required int endMs,
    required String title,
    required List<String> tags,
    required bool isLocal,
    required int mode,
    required bool forceReset,
    String? topBarLeft,
    String? topBarRight,
    List<Map<String, String>>? reminderQueue,
    bool includeReminders = false,
    bool transparentSupported = false,
  }) async {
    // Check if update is actually needed
    final currentState = endMs > 0 ? 'focusing' : 'idle';
    final bool isFocusing = endMs > 0;

    // For focusing state, always update (timer is ticking)
    // Only skip for idle state when nothing changed
    if (!forceReset &&
        !isFocusing &&
        _lastSentEndMs == endMs &&
        _lastSentState == currentState &&
        _lastSentPayload != null) {
      // No significant change for idle state, skip update
      debugPrint('[IslandDataProvider] Skip update: idle state unchanged');
      return null;
    }

    // Get style
    final style = await getStyle();
    debugPrint(
        '[IslandDataProvider] buildPayload: style=$style, endMs=$endMs, forceReset=$forceReset');
    if (style != 1) {
      // Island not enabled
      debugPrint('[IslandDataProvider] style != 1, returning null');
      return null;
    }

    // Get slot data
    final slots = await getSlotData();
    final priority = await getSlotPriority();

    String leftStr = '';
    String rightStr = '';
    IslandSlotData leftSlotData = const IslandSlotData.empty();
    IslandSlotData rightSlotData = const IslandSlotData.empty();

    // Collect active types based on priority
    final List<String> activeTypes = [];
    for (final type in priority) {
      if (slots.containsKey(type) && slots[type]!.isNotEmpty) {
        activeTypes.add(type);
      }
    }

    // Assign Left Slot
    if (activeTypes.isNotEmpty) {
      final leftType = activeTypes[0];
      leftSlotData = slots[leftType]!;
      leftStr = leftSlotData.display;

      // Assign Right Slot
      if (activeTypes.length > 1) {
        final rightType = activeTypes[1];
        // Re-fetch/re-format for right position to ensure correct padding/brackets
        rightSlotData =
            await IslandSlotProvider.getSlotData(rightType, isLeft: false);
        rightStr = rightSlotData.display;
      }
    }

    // Safety fallbacks if priority list doesn't include enough items with data
    if (leftStr.isEmpty) {
      final now = DateTime.now();
      leftStr = DateFormat('M月d日').format(now);
    }
    if (rightStr.isEmpty && leftSlotData.type != 'weekday') {
      final now = DateTime.now();
      final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      rightStr = weekdays[now.weekday - 1];
    }

    // TopBar overrides
    if (endMs == 0) {
      topBarLeft ??= leftStr;
      topBarRight ??= rightStr;
    }

    // Reminders
    if (reminderQueue == null && includeReminders) {
      reminderQueue = await IslandSlotProvider.getReminderQueue();
    }
    reminderQueue ??= [];

    // Detail source
    final detailSource = leftSlotData.isNotEmpty ? leftSlotData : rightSlotData;

    // Build payload
    final payload = <String, Object>{
      'endMs': endMs,
      'title': title,
      'tags': tags,
      'isLocal': isLocal,
      'mode': mode,
      'style': style,
      'left': leftStr,
      'right': rightStr,
      'forceReset': forceReset,
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

    // Convert to IslandPayload and build structured format
    final dto = IslandPayload.fromMap(payload);
    final theme = await getTheme();

    final focusData = _buildFocusData(dto);
    final reminderData = _buildReminderData(dto);
    final dashboardData = _buildDashboardData(dto);

    final structured = <String, dynamic>{
      'state': currentState,
      'theme': theme,
      'focusData': focusData,
      'reminderData': reminderData,
      'dashboardData': dashboardData,
      'transparentSupported': transparentSupported,
      'legacy': dto.toMap(),
    };

    // Update tracking state
    _lastSentEndMs = endMs;
    _lastSentState = currentState;
    _lastSentPayload = structured;

    return structured;
  }

  /// Build focus data section
  Map<String, dynamic> _buildFocusData(IslandPayload p) {
    final bool isFocusing = p.endMs > 0;
    String timeLabel = '';

    if (isFocusing) {
      final now = DateTime.now().millisecondsSinceEpoch;
      int secs;
      if (p.mode == 1) {
        // Count-up
        secs = (now - p.endMs) ~/ 1000;
      } else {
        // Count-down
        secs = (p.endMs - now) ~/ 1000;
      }
      if (secs < 0) secs = 0;
      final mm = (secs ~/ 60).toString().padLeft(2, '0');
      final ss = (secs % 60).toString().padLeft(2, '0');
      timeLabel = '$mm:$ss';
    }

    return {
      'title': p.title,
      'timeLabel': timeLabel,
      'isCountdown': p.mode != 1,
      'tags': p.tags,
      'syncMode': p.isLocal ? 'local' : 'remote',
      'endMs': p.endMs,
    };
  }

  /// Build reminder data section
  Map<String, dynamic> _buildReminderData(IslandPayload p) {
    if (p.reminderQueue.isEmpty) return {};
    final first = p.reminderQueue.first;
    return {
      'title': first['text'] ?? '',
      'location': first['type'] ?? '',
      'time': first['timeLabel'] ?? '',
    };
  }

  /// Build dashboard data section
  Map<String, dynamic> _buildDashboardData(IslandPayload p) {
    return {
      'leftSlot': p.topBarLeft.isNotEmpty ? p.topBarLeft : p.left,
      'rightSlot': p.topBarRight.isNotEmpty ? p.topBarRight : p.right,
    };
  }

  /// Invalidate all caches (call when data changes significantly)
  void invalidateCache() {
    _slotCache = null;
    _styleCache = null;
    _priorityCache = null;
    _themeCache = null;
  }

  /// Invalidate only slot cache (call when todos/courses change)
  void invalidateSlotCache() {
    _slotCache = null;
    // 重置追踪状态, 确保下次 buildPayload 不会被"状态未变"跳过
    _lastSentPayload = null;
  }

  /// Reset tracking state (call when switching sessions)
  void resetTrackingState() {
    _lastSentEndMs = 0;
    _lastSentState = '';
    _lastSentPayload = null;
  }

  /// Get current cached state for debugging
  Map<String, dynamic> getDebugInfo() {
    return {
      'slotCacheValid': _slotCache?.isValid(slotCacheDuration) ?? false,
      'styleCacheValid': _styleCache?.isValid(settingsCacheDuration) ?? false,
      'lastSentEndMs': _lastSentEndMs,
      'lastSentState': _lastSentState,
      'hasLastPayload': _lastSentPayload != null,
    };
  }
}
