# Feature status

Last checked against the working tree: 2026-07-20. This is a capability map,
not a release promise.

## Implemented

- Todos, groups, date-only/deadline semantics, recurrence series, completion
  history and recurrence repair/merge tools.
- Countdowns, course import/management, Pomodoro, time logs and plan blocks.
- Plan-block reminders, drag/resize interactions, statistics, and system
  calendar synchronization with persisted calendar event IDs.
- Alibaba Cloud delta sync, conflict inbox/history/rollback, collaboration and
  WebSocket-driven live updates.
- Global search with FTS5/FTS4/LIKE fallback and search-history statistics.
- Data import/export screens, theme customization, updates and onboarding.
- AI chat/actions covering todos, plan blocks, time logs, Pomodoro, countdowns,
  groups and tags. Dedicated parser/action regression tests are still sparse.
- Rule-based medal recommendations plus an ML/bandit recommendation path; the
  catalog currently contains 100 medals.
- Android widgets/background notifications/HyperOS integration, Windows island,
  macOS menu bar/widgets/island, Flutter web, React web companion, and Xiaomi
  band companion.

## Partial or platform-dependent

- Product-level todo semantics in `docs/features/todo-semantics.md` are defined,
  but the P1 implementation is not complete. Current code has introduced
  `TodoTimeMode` and capture-intent classification/confirmation; generic fixed
  schedule persistence, skip-state and remaining wording/migrations are still
  in flight.
- iOS has a Flutter host but its integration depth is behind the actively
  maintained Android, Windows and macOS surfaces.
- Calendar access, background execution, widgets and island behavior vary by
  OS capabilities and permissions.
- Cloudflare Worker behavior remains for compatibility, while new backend work
  targets the external Alibaba development server.

## Known engineering debt

- Several screens and the storage facade remain very large despite partial
  extraction.
- Native HTTP helpers currently accept invalid certificates in some flows.
- Band version constants inside sync code can drift from the manifest/package
  version and should be unified.
- Cross-platform integration tests and dedicated AI action tests need expansion.
