# Documentation index

All 36 project Markdown files in this workspace were reviewed against the working tree
on 2026-07-20. Dependency/build output Markdown is intentionally excluded.

## Current references

- `PROJECT_ARCHITECTURE.md` — code, storage, backend and platform map.
- `features/todo-semantics.md` — approved product semantics; explicitly tracks
  the remaining P1 implementation gap.
- `features/plan-blocks.md` — plan-block model and current behavior.
- `features/captcha-verification.md` — Turnstile paths by platform.
- `features/mac-support.md` — macOS integrations.
- `features/medal-recommendation.md` — rule and ML recommendation flow.
- `ai/todo-agent.md` — AI action protocol and supported actions.
- `sync/conflict-logic.md` — current client/server conflict contract.
- `../lib/README.md`, `../lib/screens/README.md`,
  `../lib/services/README.md`, and `../lib/widgets/README.md` — source maps.
- `../android/README.md`, `../windows/README.md`, and
  `../lib/windows_island/README.md` — platform implementation notes.

## Planning and historical records

Files under `archive/` and `reports/`, plus `ai/ml-optimization-plan.md`,
`sync/uni-sync-design.md`, and `ISLAND_REDESIGN_PLAN.md`, preserve design or
investigation context. Each carries a status note separating implemented code
from proposals; old checkboxes and metrics are not release guarantees.

## Private and generated notes

- `private/testing-account.md` contains test-account identifiers only; never add
  passwords, tokens or production credentials.
- `../ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` is the standard
  Flutter launch-image asset note and requires no project-specific behavior.

When implementation changes, update the nearest feature/platform document and
this index if its status or ownership changes. Prefer stable symbols and paths
over line numbers.
