# Project architecture

Last reconciled with code: 2026-07-20. Flutter package version: **5.4.22**.

## Repository map

```text
lib/                    Flutter application
  screens/              full screens and feature flows
  widgets/              reusable and feature widgets
  services/             persistence, sync and platform services
    storage/            extracted StorageService responsibilities
  windows_island/       Windows-only island UI/state/IPC
android/                Kotlin host, widgets, notifications, HyperOS, band
ios/                    iOS Flutter host
macos/                  Swift host, menu bar, widgets and native island
windows/                C++ Flutter host and installer definition
web/                    Flutter web host
webpage/web/            separate React web companion
CountDownTodo-band/      Xiaomi band companion
math-quiz-backend/       retained Cloudflare Worker compatibility backend
test/                   Flutter unit and widget tests
```

The active Alibaba Cloud server is a separate `CDT-server` checkout. Develop
against `debug/`; production code is in `math_quiz_backend/` and is not modified
as part of normal client work.

## Flutter layers

- `models.dart` defines shared entities including todos, recurrence, countdowns,
  groups, courses, plan blocks, Pomodoro, collaboration and sharing.
- Screens/widgets call domain and platform services. Several feature files are
  still large; this is a known modularization debt rather than a deliberate
  single-file architecture.
- `StorageService` is the compatibility facade and HTTP delta-sync coordinator.
  Settings, user sessions, countdowns, Pomodoro preference data and conflict
  cleanup have begun moving into `services/storage/`.
- Platform services use conditional exports so web does not import `dart:io`
  implementations and Android does not initialize Windows island code.

## Local data

- SQLite schema version: **32** in `DatabaseHelper`.
- Per-user database: `uni_sync_<username>.db`.
- Main tables include todos, groups, countdowns, courses, plan blocks, time logs,
  Pomodoro records/tags, settings, collaboration data, audit/conflict data,
  search history and medal recommendations.
- Search initializes FTS5 when available, then FTS4, then falls back to `LIKE`.
- SharedPreferences holds lightweight settings and session information; it is
  not the primary store for full synchronized datasets.

## Todo and planning semantics

- `TodoTimeMode` distinguishes unscheduled, date-only and deadline todos.
- `ItemSemanticsService` classifies capture text as todo, fixed schedule, plan
  block or confirmation-required. Generic fixed-schedule persistence is not yet
  implemented, so current capture flows warn before temporarily saving one as a
  todo.
- Recurrence uses per-occurrence UUIDs plus `recurrence_series_id`; repair,
  aliasing and deduplication protect older and cross-device data.
- `TodoPlanBlock` represents an execution window independently of a todo's due
  semantics. Blocks support planned/finished/delayed/cancelled/reminded/focusing/
  missed/skipped states, reminders, Pomodoro linkage and calendar event IDs.
- `docs/features/todo-semantics.md` defines additional approved semantics that
  are not all implemented yet.

## Sync and backend

1. Client mutations update UUID/version/timestamps and local audit state.
2. `StorageService.syncData()` sends deltas and receives server changes and
   conflicts.
3. The Alibaba server checks ownership/scope, versions and schedule overlap,
   persists conflict snapshots, and broadcasts live-update signals.
4. Client conflict screens can keep local/server data, merge supported fields,
   ignore remote items, inspect history or request rollback.

Native Android/Windows clients use direct Alibaba URLs; web uses the Zero Trust
proxy. Pomodoro awareness and collaboration also use WebSocket. The Worker under
`math-quiz-backend/` remains compatible but is no longer the default backend for
new features.

## Platform integrations

- Android: WorkManager/alarm reminder paths, five widget families, HyperOS live
  notifications, usage access, and band communication.
- Windows: standard Flutter host plus file-IPC island/floating window.
- macOS: app menu, status bar, WidgetKit widgets, launch-at-login, deep links,
  updater integration and a native island/status controller.
- Web: Flutter client, JS Turnstile integration and proxy API routing.

## Verification

Use `flutter analyze`, `flutter test`, targeted platform builds, Worker tests,
and band lint/build as relevant. Storage migrations, recurrence, conflict logic,
notification scheduling and platform guards deserve focused regression tests.
