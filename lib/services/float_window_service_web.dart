import 'package:flutter/foundation.dart';

class FloatWindowConfig {
  FloatWindowConfig._();

  static const int islandCreateCooldownMs = 1200;
  static const int snoozeDialogDelayMs = 500;
  static const double defaultIslandWidth = 160.0;
  static const double defaultIslandHeight = 56.0;
}

class FloatWindowService {
  static ValueNotifier<Map<String, dynamic>?> debugPayload =
      ValueNotifier<Map<String, dynamic>?>(null);
  static bool isWorkbenchMounted = false;

  static Future<void> init() async {}

  static Future<void> dispose() async {
    debugPayload.value = null;
    isWorkbenchMounted = false;
  }

  static void clearFocus() {
    debugPayload.value = null;
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
    bool includeReminders = false,
    bool isPaused = false,
    int? accumulatedMs,
    int? pauseStartMs,
    String? note,
  }) async {}

  static Future<void> resetPositions() async {}

  static Future<void> triggerReminderCheck() async {}

  static void invalidateCache() {}

  static void invalidateSlotCache() {}

  static Map<String, dynamic> getDebugInfo() {
    return const {
      'platform': 'web',
      'enabled': false,
      'reason': 'Windows island is not available on Flutter Web',
    };
  }
}
