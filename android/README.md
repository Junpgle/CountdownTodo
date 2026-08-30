# Android implementation

The Android host contains more than a standard Flutter bootstrap. Last reviewed:
2026-07-20.

## Native components

- `MainActivity.kt`: method channels, HyperOS/HyperIsland live notifications,
  screen-time usage access, background notification integration and band
  communication.
- `BackgroundNotificationScheduler.kt`, `NotificationPollWorker.kt`,
  `ReminderAlarmReceiver.kt`, and `ReminderService.kt`: background polling,
  alarms and reminder delivery.
- `BandCommunicationPlugin.kt`: bridge to the Xiaomi band companion.
- Multiple widget families: combined todo, todo-only, countdown-only, course-only,
  focus-only, recurrence, habit and finance widgets.

The Android 17 Xiaomi freeform inset/rendering incident and its verification
record are maintained in [`../docs/reports/android-17-xiaomi-freeform-flutter.md`](../docs/reports/android-17-xiaomi-freeform-flutter.md).

Resources and declarations live under `android/app/src/main/res/` and
`AndroidManifest.xml`. Update both code and manifest/resource entries when
adding a widget, receiver, service, permission or channel.

## Platform boundary

Android must never import or initialize Windows island/floating-window logic.
Use `Platform.isWindows` or conditional exports in Flutter and keep Kotlin
changes Android-specific. Notification behavior must account for runtime
permission, exact-alarm/background restrictions and vendor-specific HyperOS
capabilities.

## Verification

```bash
flutter analyze
flutter test
flutter build apk
# or
flutter run -d <android-device>
```

There is no repository `verify_fix.ps1` script. Exercise reminders, widgets,
background polling, HyperOS behavior and band messages on appropriate devices.
