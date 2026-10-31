# Documentation index

Index last reconciled: 2026-10-31. Current-state documents keep their own review
dates; archived plans and incident reports retain their historical dates.
Dependency/build output Markdown is intentionally excluded.

## Current references

- `PROJECT_ARCHITECTURE.md` — code, storage, backend and platform map.
- `features/todo-semantics.md` — approved product semantics; tracks the remaining
  P1 gaps and the capability-gated generic fixed-schedule sync boundary.
- `habits.md` — habit center design; core capabilities are implemented in
  `../lib/features/habits/` (check-ins, hold guard, sleep coaching, widget check-in).
- `features/plan-blocks.md` — plan-block model, buffers, drafts, and backlog behavior.
- `features/plan-availability-buffers.md` — plan availability buffer mechanics.
- `features/plan-backlog.md` — plan backlog list and capacity planning.
- `features/plan-cleanup.md` — historical plan cleanup and completed todo associations.
- `features/plan-editor-drafts.md` — plan block editor drafts and concurrency protection.
- `features/plan-review.md` — plan conflict review and day overview.
- `features/plan-split-scheduling.md` — split scheduling mechanics for todos.
- `features/finance.md` — personal finance design, storage boundary, calendar and sync notes.
- `features/finance-intro-guide.md` — personal finance introductory guide and help center.
- `features/private-journal.md` — local-only private journal and trash bin lifecycle.
- `features/data-backup.md` — JSON export, domain-selective restore, review receipts and UUID semantics.
- `features/global-search.md` — searchable data sources, result destinations,
  direct feature navigation, shared-container animation and remote-source limits.
- `features/ai-settings-navigation.md` — AI context-driven settings navigation and routing.
- `features/quick-voice-chat.md` — quick voice chat integration and interaction flows.
- `features/captcha-verification.md` — Turnstile paths by platform.
- `features/mac-support.md` — macOS integrations.
- `features/medal-recommendation.md` — rule and ML recommendation flow.
- `ai/todo-agent.md` — AI action protocol and supported actions.
- `sync/conflict-logic.md` — current client/server conflict contract.
- `../lib/README.md`, `../lib/screens/README.md`,
  `../lib/services/README.md`, and `../lib/widgets/README.md` — source maps.
- `../globalize.md` — shared-component and refactor inventory.
- `../feature.md` — capability map of implemented and partial features.
- `../android/README.md`, `../windows/README.md`, and
  `../lib/windows_island/README.md` — platform implementation notes.

## Planning and historical records

Files under `archive/` and `reports/`, plus `ai/ml-optimization-plan.md`,
`sync/uni-sync-design.md`, and `ISLAND_REDESIGN_PLAN.md`, preserve design or
investigation context. Each carries a status note separating implemented code
from proposals; old checkboxes and metrics are not release guarantees.

- `reports/android-17-xiaomi-freeform-flutter.md` — Android 17 Xiaomi freeform
  inset and Flutter rendering compatibility incident record.

## Private and generated notes

- `private/testing-account.md` contains test-account identifiers only; never add
  passwords, tokens or production credentials.
- `../ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` is the standard
  Flutter launch-image asset note and requires no project-specific behavior.

When implementation changes, update the nearest feature/platform document and
this index if its status or ownership changes. Prefer stable symbols and paths
over line numbers.
