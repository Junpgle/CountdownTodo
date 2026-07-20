# Uni-Sync design: current contract and former goals

The former “V4.0 design bible” was aspirational. This reconciled description is
the code-facing contract as of 2026-07-20.

## Consistency model

- Each core object has a UUID and generally carries version, updated timestamp,
  device ID, deletion and conflict metadata.
- Local writes persist first and create operation/audit state. HTTP sync sends
  deltas since the last sync time and merges server objects back into SQLite.
- The Alibaba server detects version conflicts by comparing client/server
  versions, timestamps and business data. It stores a conflict snapshot instead
  of silently overwriting the disputed record.
- Schedule-overlap detection is a separate concern. The user setting controls
  client persistence/display of schedule conflicts, not version conflicts.
- Occurrences in the same non-empty `recurrence_series_id` are excluded from
  schedule-overlap conflicts. Series-ID-only backfill can be treated as a safe
  migration rather than a business edit.

## Resolution and history

- Conflict inbox supports local/server choices and entity-specific merges.
- Keeping local data bumps version/updated time, clears conflict metadata and
  creates an operation for a later push.
- Accepting server data clears stale local operations so the discarded version
  is not uploaded again.
- The debug server exposes authenticated history, rollback, ignore-remote and
  conflict-resolution routes and validates user/team access.

## Network and scope

- Active server development is in external `CDT-server/debug/`; production is
  protected under `CDT-server/math_quiz_backend/`.
- Native clients use direct Alibaba HTTP/WebSocket endpoints; web uses the
  Cloudflare Zero Trust proxy.
- The in-repository Worker is a compatibility implementation and can differ from
  newer Alibaba routes.

## Former goals not guaranteed

Universal smart merge, time-window atomic rollback previews, Proof-of-Work,
network path discovery, permanent offsite audit archives and identical UX on
every platform are not established current contracts. Add them only with schema,
protocol, authorization, migration and test plans.
