# macOS support

Last reviewed against version 5.4.22: 2026-07-20.

## Implemented integrations

- Flutter desktop host built for `arm64`.
- macOS app menu and status-bar controls.
- Five WidgetKit widgets fed by the Flutter widget service.
- Launch at login, deep links, update handling and permission-aware platform
  services.
- Native island/status display through `MacPomodoroStatusBarController.swift`.
  It can surface focus state, reminders, clipboard links, ongoing activity and
  media information, including the available NetEase lyric fallback.

Island preferences include enablement, reminders, clipboard links, display on
devices without a notch, and shortcut behavior. Flutter configures the native
controller through the macOS window service; Windows island code is unrelated.

## Build and verify

```bash
./scripts/sync_macos_version.sh
./scripts/build_macos.sh
# or
flutter run -d macos
```

Check signing/entitlements, menu commands, launch-at-login, widgets, deep links,
notifications, island behavior with and without a notch, and updater behavior.
Do not commit signing certificates or private deployment configuration.
