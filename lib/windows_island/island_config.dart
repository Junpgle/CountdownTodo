import 'dart:ui';

/// Island module configuration constants.
/// Centralizes all magic numbers and default values for easy customization.
class IslandConfig {
  IslandConfig._();

  // ── Window Defaults ──────────────────────────────────────────────────────

  /// Default island window width
  static const double defaultWidth = 160.0;

  /// Default island window height
  static const double defaultHeight = 56.0;

  /// Minimum window width for detection
  static const int detectionMaxWidth = 800;

  /// Minimum window height for detection
  static const int detectionMaxHeight = 600;

  // ── Timing ───────────────────────────────────────────────────────────────

  /// File IPC polling interval
  static const Duration ipcPollInterval = Duration(milliseconds: 200);

  /// Window ready timeout
  static const Duration readyTimeout = Duration(milliseconds: 2000);

  /// FFI HWND search retry interval
  static const Duration ffiRetryInterval = Duration(milliseconds: 100);

  /// FFI HWND search max attempts
  static const int ffiMaxAttempts = 100;

  /// Hover enter debounce delay
  static const Duration hoverEnterDelay = Duration(milliseconds: 100);

  /// Hover exit debounce delay
  static const Duration hoverExitDelay = Duration(milliseconds: 120);

  /// Minimum stay duration after hover expand
  static const Duration hoverMinStay = Duration(milliseconds: 400);

  /// State transition debounce window
  static const int transitionDebounceMs = 200;

  /// Payload debounce delay
  static const Duration payloadDebounce = Duration(milliseconds: 50);

  /// Bounds save enable delay after init
  static const Duration boundsSaveEnableDelay = Duration(seconds: 3);

  /// Bounds save ready delay after enable
  static const Duration boundsSaveReadyDelay = Duration(seconds: 2);

  /// Bounds polling interval
  static const Duration boundsPollInterval = Duration(seconds: 2);

  /// Reminder check interval
  static const Duration reminderCheckInterval = Duration(seconds: 10);

  /// Initial reminder check delay
  static const Duration initialReminderCheckDelay = Duration(seconds: 5);

  /// Copied link auto-dismiss duration
  static const Duration copiedLinkDismissDuration = Duration(seconds: 10);

  /// Send payload max retry count
  static const int sendMaxRetries = 5;

  /// Send payload initial delay
  static const int sendInitialDelayMs = 50;

  /// Send payload max delay
  static const int sendMaxDelayMs = 800;

  /// Recreate island cooldown
  static const int recreateCooldownMs = 1200;

  /// Window position restore delay
  static const Duration windowRestoreDelay = Duration(milliseconds: 500);

  /// Window init post-setup delay
  static const Duration windowPostSetupDelay = Duration(milliseconds: 400);

  // ── UI Sizes ─────────────────────────────────────────────────────────────

  /// Get target size for each island state
  static Size sizeForState(IslandStateConfig state,
      {bool hasSubtitle = false, String? expandedPart}) {
    switch (state) {
      case IslandStateConfig.idle:
        return const Size(120, 34);
      case IslandStateConfig.focusing:
        return const Size(100, 46);
      case IslandStateConfig.hoverWide:
        return const Size(380, 46);
      case IslandStateConfig.splitAlert:
        return const Size(300, 36);
      case IslandStateConfig.stackedCard:
        return const Size(280, 140);
      case IslandStateConfig.finishConfirm:
      case IslandStateConfig.abandonConfirm:
      case IslandStateConfig.finishFinal:
        return const Size(260, 130);
      case IslandStateConfig.reminderPopup:
        return Size(320, hasSubtitle ? 180 : 150);
      case IslandStateConfig.reminderSplit:
        if (expandedPart != null) {
          return Size(320, hasSubtitle ? 340 : 300);
        }
        return const Size(480, 46);
      case IslandStateConfig.reminderCapsule:
        return const Size(160, 46);
      case IslandStateConfig.copiedLink:
        return const Size(340, 46);
    }
  }

  // ── Colors ───────────────────────────────────────────────────────────────

  /// Background color
  static const Color bgColor = Color(0xFF1C1C1E);

  /// Transparent background for split state
  static const Color transparentBg = Color(0x00000000);

  /// Black overlay for scaffold
  static const Color scaffoldBg = Color(0xFF000000);

  /// Success green
  static const Color successColor = Color(0xFF4CAF50);

  /// Danger red
  static const Color dangerColor = Color(0xFFD32F2F);

  /// Warning orange
  static const Color warningColor = Color(0xFFFF9800);

  /// Focus purple
  static const Color focusColor = Color(0xFF6366F1);

  // ── Animation ────────────────────────────────────────────────────────────

  /// Standard transition duration
  static const Duration transitionDuration = Duration(milliseconds: 200);

  /// Content switch duration
  static const Duration switchDuration = Duration(milliseconds: 300);

  /// Initial scale for switch animation
  static const double switchScaleBegin = 0.92;

  /// Final scale for switch animation
  static const double switchScaleEnd = 1.0;

  // ── Border Radius ────────────────────────────────────────────────────────

  /// Standard capsule border radius
  static const double capsuleRadius = 28.0;

  /// Card-style border radius
  static const double cardRadius = 20.0;

  /// Small button border radius
  static const double buttonRadius = 18.0;

  /// Mini button border radius
  static const double miniButtonRadius = 13.0;

  // ── File Paths ───────────────────────────────────────────────────────────

  /// Action IPC file name
  static const String actionFileName = 'island_action.json';

  /// Todo data file name
  static const String todoFileName = 'island_todos.json';

  /// Window ID file prefix
  static const String windowIdFilePrefix = 'island_wid_';

  // ── Window ID ────────────────────────────────────────────────────────────

  /// Default island ID
  static const String defaultIslandId = 'island-1';
}

/// Enum for island states (config-level, for size calculation)
enum IslandStateConfig {
  idle,
  focusing,
  hoverWide,
  splitAlert,
  stackedCard,
  finishConfirm,
  abandonConfirm,
  finishFinal,
  reminderPopup,
  reminderSplit,
  reminderCapsule,
  copiedLink,
}
