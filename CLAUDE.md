# Countdown Todo development context

This file is a compact implementation map for coding assistants. It was last
checked against the working tree on 2026-07-20; `AGENTS.md` contains the
authoritative repository rules.

## Current baseline

- Flutter package version: `5.4.22` (`pubspec.yaml`).
- Dart constraint: `>=3.1.0 <4.0.0`.
- Local SQLite schema: version 32.
- Main targets: Android, Windows, macOS, and Flutter web. iOS host files exist,
  but feature parity is not documented as complete.
- `lib/models.dart` contains the shared sync models; `StorageService` remains
  the main orchestration facade while settings, session, countdown, Pomodoro,
  and cleanup responsibilities are being extracted under
  `lib/services/storage/`.

## Data and synchronization

- A signed-in user gets a local database named `uni_sync_<username>.db`.
- Most sync entities carry UUID, version, timestamps, device ID, deletion and
  conflict metadata. `StorageService.syncData()` coordinates the HTTP delta
  sync; Pomodoro also has service-level cloud/WebSocket behavior.
- Recurring todos carry `recurrence_series_id` with snake/camel compatibility.
  The client repairs missing series IDs, aliases and occurrences and performs
  series-aware deduplication. Do not simplify those paths without regression
  tests.
- Todo time semantics now distinguish unscheduled, date-only and deadline
  items through `TodoTimeMode`; execution windows belong to `TodoPlanBlock`.
- Search probes FTS5, falls back to FTS4, then SQL `LIKE`.

## Network topology

- Alibaba Cloud is the active backend. Its checkout is outside this repository:
  `CDT-server/debug/` for development and `CDT-server/math_quiz_backend/` for
  production.
- Native clients select direct Alibaba endpoints; web uses
  `https://api-cdt.junpgle.me/` through Cloudflare Zero Trust.
- `math-quiz-backend/` is the retained Cloudflare Worker compatibility
  implementation, not the primary place for new backend work.
- Authentication, sync and multi-device Pomodoro depend on both HTTP and
  WebSocket. Preserve test/production and web/native selection logic.

## High-risk areas

- `lib/storage_service.dart`, recurrence repair, conflict resolution and audit
  versioning.
- Android notification/HyperOS integration in `MainActivity.kt`.
- Windows island IPC and macOS native island/status-bar bridges.
- Calendar all-day conversion: only date-only todos should become all-day
  events; a genuine cross-day deadline is not an all-day item.
- Global HTTP overrides currently accept otherwise invalid certificates for
  selected native flows. Treat this as a security debt; do not broaden it.

Use `docs/README.md` as the documentation index and
`docs/features/todo-semantics.md` for the product semantics that are not yet
fully implemented.
