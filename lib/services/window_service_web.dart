class WindowService {
  static Future<bool> Function()? onShowCloseConfirm;

  static Future<void> init() async {}

  static Future<void> restoreStartupBoundsAndRepairViewport() async {}

  static void schedulePostShowViewportRepair() {}

  static Future<void> configureMacIsland() async {}

  static Future<bool> setMacIslandVisibilityShortcut({
    required String key,
    required bool command,
    required bool option,
    required bool control,
    required bool shift,
  }) async =>
      false;
}
