# `lib/` source map

Last reviewed: 2026-08-25.

- `main.dart`: bootstrap, database/session setup, platform initialization and
  global Liquid Glass theme wiring.
- `models.dart`: synchronized domain models and enums; extended models live in
  `models/` (AI actions, chat messages, medal ML, minor mode, widget snapshots).
- `storage_service.dart`: persistence compatibility facade, todo/recurrence and
  HTTP delta-sync orchestration.
- `screens/`: application flows and feature pages.
- `widgets/`: reusable and feature-specific presentation.
- `services/`: database, network, sync, AI, search, calendar, notifications,
  Pomodoro, export/import and platform adapters.
- `services/storage/`: extracted settings, sessions, countdown, Pomodoro and
  conflict-cleanup storage responsibilities.
- `features/`: self-contained feature modules with their own models/services/UI:
  - `habits/`: habit center, check-ins, sleep coaching.
  - `journal/`: local private journal.
  - `thirty_day_challenge/`: 30-day challenge list, cloud templates, sharing.
- `theme/`: theme extensions, including the Liquid Glass theme application
  (`app_liquid_glass_theme.dart`) and habit adaptation panel styles.
- `utils/`: shared formatting, dialogs, colors, navigation and helpers.
- `course_import/`: course parsing/import logic.
- `windows_island/`: Windows-only island state, UI and file IPC.

Web-safe code must not import `dart:io`; use existing conditional exports.
Platform integrations should stay guarded and UI colors should derive from the
Material 3 `ColorScheme`.
