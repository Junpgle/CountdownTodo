# `lib/` source map

Last reviewed: 2026-07-20.

- `main.dart`: bootstrap, database/session setup and platform initialization.
- `models.dart`: synchronized domain models and enums.
- `storage_service.dart`: persistence compatibility facade, todo/recurrence and
  HTTP delta-sync orchestration.
- `screens/`: application flows and feature pages.
- `widgets/`: reusable and feature-specific presentation.
- `services/`: database, network, sync, AI, search, calendar, notifications,
  Pomodoro, export/import and platform adapters.
- `services/storage/`: extracted settings, sessions, countdown, Pomodoro and
  conflict-cleanup storage responsibilities.
- `utils/`: shared formatting, dialogs, colors, navigation and helpers.
- `course_import/`: course parsing/import logic.
- `windows_island/`: Windows-only island state, UI and file IPC.

Web-safe code must not import `dart:io`; use existing conditional exports.
Platform integrations should stay guarded and UI colors should derive from the
Material 3 `ColorScheme`.
