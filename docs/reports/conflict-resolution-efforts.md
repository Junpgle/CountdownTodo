# Multi-device conflict recurrence: investigation record

Status: historical incident report, reconciled 2026-07-20.

## Symptom

After choosing “use server for all” on a phone, equivalent conflicts could return
on the next sync. The issue crossed local SQLite, unsynced op logs, multiple
clients, server conflict flags/snapshots and legacy backend paths; it was not
only a conflict-inbox rendering bug.

## Root causes found across the fixes

- Accepting the server copy could leave a stale local operation that uploaded
  the rejected data again.
- Clearing a local flag without clearing/acknowledging the server snapshot let
  the server return the same conflict.
- Version and schedule conflicts were mixed even though their enablement and
  resolution semantics differ.
- Server/client field normalization, timestamps and version bumps were not
  consistently applied to every entity.
- More recently, recurrence-series ID migration could look like a content edit
  or let occurrences from one series conflict with one another.

## Current safeguards

- Accept-server resolution removes stale local operations before the next push.
- Keep-local resolution deliberately creates a new operation with advanced
  metadata.
- Authenticated server resolution clears conflict state and updates
  entity-specific fields; team todo access is checked.
- Schedule detection is separately switchable and local ignored pairs are
  remembered.
- Same-series occurrences are excluded from schedule overlap; guarded
  series-ID-only backfill does not create a version conflict.
- History and rollback paths retain auditability, and rollback protects a current
  series ID when an older snapshot does not contain one.

## Current locations

The old `aliyun_debug/server.js` path no longer exists. Server logic is modular
in the external `CDT-server/debug/routes/` and `services/` directories. Client
logic remains primarily in `lib/storage_service.dart` and
`lib/screens/conflict_inbox_screen.dart`.

## Regression checklist

Test two devices editing the same item, accept-server and keep-local followed by
two sync cycles, deleted records, team authorization, batch resolution, old
snake/camel payloads, schedule detection on/off, recurring series with a missing
ID, and rollback of a pre-series snapshot. A conflict is fixed only when it does
not reappear on a subsequent clean sync.
