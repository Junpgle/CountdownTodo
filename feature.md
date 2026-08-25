# Feature status

Last checked against the working tree: 2026-08-25. This is a capability map,
not a release promise.

## Implemented

- Todos, groups, date-only/deadline semantics, recurrence series, completion
  history and recurrence repair/merge tools.
- Countdowns, course import/management, Pomodoro, time logs and plan blocks.
- Plan-block reminders, drag/resize interactions, statistics, and system
  calendar synchronization with persisted calendar event IDs.
- Habit center (`lib/features/habits/`): independent check-in model with
  streak/completion statistics, reminders, widget check-in, sleep-duration
  coaching with progressive goals and legacy sleep-log migration.
- Local private journal (`lib/features/journal/`) kept on-device only, with a
  media picker that degrades gracefully on web.
- Thirty-day challenge (`lib/features/thirty_day_challenge/`) with the built-in
  30-item list, cloud template catalog and share-code parsing.
- Alibaba Cloud delta sync, conflict inbox/history/rollback, collaboration and
  WebSocket-driven live updates.
- Global search with FTS5/FTS4/LIKE fallback and search-history statistics.
- Data import/export screens, theme customization, updates (including Wi-Fi
  auto-download of update packages) and onboarding.
- AI chat/actions covering todos, fixed schedules, plan blocks, time logs,
  Pomodoro, countdowns, groups and tags. Dedicated parser/action regression
  tests are still sparse.
- Rule-based medal recommendations plus an ML/bandit recommendation path; the
  catalog currently contains 100 medals.
- Home sidebar configuration (hide/reorder entries), minor mode with an
  age-permission matrix, and an optional Liquid Glass visual effect
  (`liquid_glass_effect_service.dart` + `OptionalLiquidGlassSurface`) applied to
  home cards, the bottom navigation bar and quick actions, with standard/enhanced
  modes controlled from the animation settings page.
- Android widgets/background notifications/HyperOS integration, Windows island,
  macOS menu bar/widgets/island (including Apple Music media info), Flutter
  web, React web companion, and Xiaomi band companion.

## Partial or platform-dependent

- Product-level todo semantics in `docs/features/todo-semantics.md` are defined;
  generic fixed schedules now ship with creation/editing, recurrence-series
  materialization, conflict detection, calendar export, backup support and
  capability-gated Alibaba debug/release sync. Cross-device deployment
  verification, skip-state, relation editing, reminder scheduling for
  fixed schedules, and the remaining wording/migrations are still in flight.
- iOS has a Flutter host but its integration depth is behind the actively
  maintained Android, Windows and macOS surfaces.
- Calendar access, background execution, widgets and island behavior vary by
  OS capabilities and permissions.
- Cloudflare Worker behavior remains for compatibility, while new backend work
  targets the external Alibaba development server.

## Known engineering debt

- Several screens and the storage facade remain very large despite partial
  extraction; `home_dashboard`, `course_screens` and `todo_chat_screen` are
  split into `part` files but still need independently testable extraction.
- Native HTTP helpers currently accept invalid certificates in some flows.
- Band version constants inside sync code can drift from the manifest/package
  version and should be unified.
- Cross-platform integration tests and dedicated AI action tests need expansion.
