# `lib/` source map

Last reviewed: 2026-10-31.

- `main.dart`: bootstrap, database/session setup, platform initialization and
  global Liquid Glass theme wiring.
- `models.dart`: synchronized domain models and enums; extended models live in
  `models/` (AI actions, chat messages, medal ML, minor mode, widget snapshots).
- `storage_service.dart`: persistence compatibility facade, todo/recurrence and
  HTTP delta-sync orchestration.
- `screens/`: application flows, feature pages, and `help/feature_explorer_screen.dart`.
- `widgets/`: reusable and feature-specific presentation (including performance floating window).
- `services/`: database, network, sync, AI, search, settings catalog, calendar, notifications,
  Pomodoro, export/import, wallpaper caching and platform adapters.
- Global search combines `services/search_service.dart` with
  `services/global_search_extra_service.dart`; see `docs/features/global-search.md`.
- `services/storage/`: extracted settings, sessions, countdown, Pomodoro and
  conflict-cleanup storage responsibilities.
- `features/`: self-contained feature modules with their own models/services/UI:
  - `habits/`: habit center, check-ins, sleep coaching, hold-checkin guard.
  - `journal/`: local private journal with trash lifecycle.
  - `thirty_day_challenge/`: 30-day challenge list, cloud templates, sharing.
  - `finance/`: personal finance, transactions, budgets, recurring rules, loans, calendar and trends.
- `theme/`: theme extensions, including the Liquid Glass theme application
  (`app_liquid_glass_theme.dart`) and habit adaptation panel styles.
- `utils/`: shared formatting, dialogs, colors, navigation and helpers.
- `course_import/`: course parsing/import logic.
- `windows_island/`: Windows-only island state, UI and file IPC.

Web-safe code must not import `dart:io`; use existing conditional exports.
Platform integrations should stay guarded and UI colors should derive from the
Material 3 `ColorScheme`.
