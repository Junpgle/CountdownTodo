enum MacPomodoroAction { togglePause, stopFocus }

class MacPomodoroStatusBarService {
  static Stream<MacPomodoroAction> get onAction => const Stream.empty();

  static Future<void> init() async {}

  static void clearNative() {}

  static void dispose() {}
}
