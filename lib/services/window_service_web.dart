class WindowService {
  static Future<bool> Function()? onShowCloseConfirm;

  static Future<void> init() async {}

  static Future<void> restoreStartupBoundsAndRepairViewport() async {}

  static void schedulePostShowViewportRepair() {}
}
