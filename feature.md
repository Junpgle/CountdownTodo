# Feature status

Reconciled against the working tree: 2026-10-31 (v7.22.6). This is a capability map,
not a release promise; historical review dates are preserved in respective docs.

## Implemented

- Todos, groups, date-only/deadline semantics, unscheduled semantics, recurrence series,
  skip-this-period state, completion history, recurrence repair/merge tools, and trash series restore/purge.
- Countdowns, course import/management, Pomodoro, time logs and plan blocks.
- Plan-block reminders, drag/resize interactions, statistics, system calendar
  synchronization with persisted calendar event IDs, availability buffers, backlog capacity planning, and dynamic timeline track layout.
- Fixed schedules (`fixed_schedules`): dedicated model with recurrence series, conflict detection,
  bidirectional relations with todos, rescheduling impact review, preparation buffer recommendations,
  and read-only schedule placeholder mapping in time log.
- Habit center (`lib/features/habits/`): independent check-in model with streak/completion
  statistics, reminders, widget check-in, hold-to-checkin guard against accidental taps,
  focus habit Pomodoro linkage, sleep-duration coaching with progressive goals and legacy sleep-log migration.
- Local private journal (`lib/features/journal/`): kept on-device only, with media picker,
  concurrent edit protection, and a trash bin supporting restoration and permanent deletion of physical media.
- Thirty-day challenge (`lib/features/thirty_day_challenge/`): built-in 30-item list, cloud template catalog,
  independent check-in, focus session linkage, and share-code parsing.
- Personal finance (`lib/features/finance/`): offline-first transactions (expense, income, refund),
  calendar card view, precise category ledger filtering, monthly cumulative balance trends with drill-down,
  future scheduled commitments & manual future cash flow, monthly & category budgets, recurring rules,
  installment groups, loans, quick entry templates, and CSV/JSON export/restore.
- Feature Explorer & Guidance (`lib/screens/help/`): classified feature knowledge base, v7.22 new feature
  walkthrough, direct feature navigation, and interactive exploration progress tracking.
- Alibaba Cloud delta sync, conflict inbox/history/rollback, collaboration, sync health center, and WebSocket-driven live updates.
- Global search & Settings search: FTS5/FTS4/LIKE fallback across core SQLite records, finance,
  journal, schedules, plan blocks, check-ins, challenges, AI chat and team data; direct feature navigation;
  in-app settings search (`app_settings_catalog.dart`) with fuzzy match and deep-link routing.
- Data backup & restore: JSON v2 export and domain-selective restore (todos/schedules, courses, focus,
  habits, challenge, finance, preferences) with pre-restore review and domain receipts.
- Animation & Rendering Performance: real-time FPS & delivery rate metrics dashboard in animation settings,
  GPU/CPU dynamic rendering pressure evaluation, `AnimationPerformanceFloatingWindow` performance overlay,
  Liquid Glass shader caching, and downsampled image memory controls.
- Wallpapers & Themes: preset wallpaper direct rendering to avoid startup flash, Bing daily wallpaper
  local caching with failure retry, Liquid Glass visual effects with standard/enhanced modes, and dynamic Material 3 color extraction.
- AI chat/actions covering todos, fixed schedules, plan blocks, time logs, Pomodoro, countdowns, groups,
  tags, settings navigation, and finance drafts / read / update / delete operations.
- Rule-based medal recommendations plus an ML/bandit recommendation path; the catalog currently contains 100 medals.
- Home sidebar configuration (hide/reorder entries), minor mode with an age-permission matrix.
- Android widgets/background notifications/HyperOS integration, Windows island, macOS menu bar/widgets/island
  (including Apple Music media info), Flutter web, React web companion, and Xiaomi band companion.

## Partial or platform-dependent

- Product-level todo semantics in `docs/features/todo-semantics.md` are defined;
  fixed schedules ship with creation/editing, recurrence materialization, conflict detection,
  calendar export, backup support, todo relations and capability-gated Alibaba debug/release sync.
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
