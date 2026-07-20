# Services

Last reviewed: 2026-07-20.

## Core areas

- `database_helper.dart`: per-user SQLite schema v32, migrations, FTS fallback
  and data access.
- `api_service.dart`, `environment_service.dart`: backend URL/environment and
  authenticated HTTP selection.
- `storage_service.dart` (one directory above): main sync facade; extracted
  modules live in `storage/`.
- `pomodoro_service.dart`, `pomodoro_sync_service.dart`: local focus lifecycle,
  cloud records and WebSocket device awareness.
- `calendar_sync_service.dart`: todo/plan-block system calendar mapping.
- `item_semantics_service.dart`: deterministic capture classification between
  todos, fixed schedules and plan blocks; fixed-schedule persistence remains a
  later phase.
- `notification_service_*` and `todo_notification_policy.dart`: platform
  scheduling and date/deadline policy.
- `search_service.dart`: global search ranking over database results.
- `llm_service.dart` plus AI parser/executor services: configured provider and
  structured actions.
- `data_export_service.dart` and migration services: portable data flows.

Platform-dependent services use `_io.dart`, `_web.dart`, stub files and
conditional exports for notifications, updates, widgets, calendar, windows,
Turnstile, migration and LAN sync. Preserve these boundaries.

New persistence logic should include migration and rollback considerations;
network work must preserve native direct URLs, web proxying and WebSockets.
