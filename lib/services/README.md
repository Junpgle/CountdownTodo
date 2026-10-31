# Services

Last reviewed: 2026-10-31.

## Core areas

- `database_helper.dart`: per-user SQLite schema (version tracked in
  `database_schema_history.dart`, currently v60), migrations, FTS fallback and
  data access.
- `api_service.dart`, `environment_service.dart`: backend URL/environment and
  authenticated HTTP selection.
- `storage_service.dart` (one directory above): main sync facade; extracted
  modules live in `storage/`.
- `pomodoro_service.dart`, `pomodoro_sync_service.dart`: local focus lifecycle,
  cloud records and WebSocket device awareness.
- `calendar_sync_service.dart`: todo/plan-block/fixed-schedule system calendar
  mapping.
- `item_semantics_service.dart`: deterministic capture classification between
  todos, fixed schedules and plan blocks. Fixed schedules use their own model,
  persistence, recurrence materialization, reminders, todo relations and sync path
  (`fixed_schedule_recurrence_service.dart`, `fixed_schedule_service.dart`).
- `notification_service_*` and `todo_notification_policy.dart`: platform
  scheduling and date/deadline policy.
- `search_service.dart`: global search ranking, database-backed results and direct feature navigation;
  `global_search_extra_service.dart` adds finance, journal, schedules, plan
  blocks, check-ins, challenges, AI chat and team records; `app_settings_catalog.dart`
  supports in-app settings search.
- `llm_service.dart` plus AI parser/executor services: configured provider and
  structured actions.
- `data_export_service.dart` and migration services: portable data flows, JSON v2 backup,
  and domain-selective restore with receipts.
- `bing_wallpaper_service.dart`: Bing daily wallpaper fetching, same-day caching and failure retry.
- `liquid_glass_effect_service.dart`: opt-in Liquid Glass configuration
  (enablement + standard/enhanced mode) consumed by the theme and glass
  surfaces; initialization failures must degrade to Material fallbacks.
- `sidebar_menu_service.dart`, `home_layout_service.dart`,
  `feature_tip_service.dart`: home sidebar/menu configuration, home layout
  groups, and feature tips/onboarding guidance.
- `minor_mode_service.dart` / `minor_mode_policy.dart`: minor-mode state,
  age-band mapping and permission matrix.

Platform-dependent services use `_io.dart`, `_web.dart`, stub files and
conditional exports for notifications, updates, widgets, calendar, windows,
Turnstile, migration and LAN sync. Preserve these boundaries.

New persistence logic should include migration and rollback considerations;
network work must preserve native direct URLs, web proxying and WebSockets.
