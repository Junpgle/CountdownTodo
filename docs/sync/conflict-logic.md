# Current conflict logic

Last verified against the Flutter client and external Alibaba debug/release
servers: 2026-08-25.

## Two conflict classes

### Version conflicts

The server compares a submitted object with the stored UUID/version/timestamps
and business fields. Non-recurring todos retain the existing guarded conflict
flow. Recurring todos and their generated instances use strict LWW ordering:
`updated_at` wins first, and `version` is consulted only when timestamps are
equal. A higher version can therefore never make an older recurring snapshot
overwrite newer content or a newer tombstone.

When a stale recurring payload is rejected, the server forces a full todo
response for that request so an old client converges to the authoritative row
even if its normal sync watermark has already advanced. An exact
timestamp/version tie with different business data remains a version conflict;
it is not silently resolved. The Flutter downlink merge uses the same ordering
and does not apply conflicted recurring snapshots.

Fixed schedules use the same strict ordering. A stale fixed-schedule write or
tombstone is rejected even when it carries a higher version, and that response
forces a full fixed-schedule downlink so the client converges past an advanced
watermark. Team members may edit shared schedule content, but only the database
owner may clear `team_uuid` or transfer the schedule to another joined team.

Todo comparison includes content/completion/deletion, dates, recurrence and
`recurrence_series_id`, custom interval/end date, remark/group/team/category,
collaboration type, reminder, all-day/date flag and device metadata. Other
entities use their own business fields.

### Schedule conflicts

Local scanning and the Alibaba `checkItemConflict` helper detect overlapping
timed todos. Date-only (`is_all_day`) and deleted objects are excluded by the
server query. Objects with the same non-empty recurrence series ID do not
conflict with one another.

`conflict_detection_enabled` is scoped per signed-in user and defaults to
`false`. When disabled, the client clears local schedule flags, ignores returned
schedule conflicts and hides schedule indicators; version conflicts remain.
Ignored overlap pairs are stored by a stable pair key.

## Resolution

- Keep local: `resolveConflictLocally(createOplog: true)` clears conflict data,
  advances metadata and queues the chosen version; the server
  `/api/sync/resolve_conflict` route applies the authenticated entity update.
- Accept server: the client applies the server snapshot and removes stale
  pending operations so the losing local data cannot immediately recreate the
  conflict; the server marks the conflict resolved.
- Batch operations use the same entity-specific paths. Todos, countdowns,
  groups, Pomodoro records and Pomodoro tags are supported by the server route.
- History/rollback are separate authenticated routes. Rollback advances version
  and preserves a todo's current recurrence-series ID if an older snapshot lacks
  it.

## Recurrence migration safeguards

The client repairs missing series IDs and can clear conflicts caused only by
series-ID migration when all material business fields agree. Genuine content,
completion, time or recurrence differences stay visible. The server likewise
treats an empty→filled series-ID backfill as safe under its guarded conditions.
This compatibility backfill is the only recurring-series metadata exception to
the normal LWW rejection path.

## Source map

- Client: `lib/storage_service.dart`, `lib/screens/conflict_inbox_screen.dart`,
  `lib/models.dart`, `lib/services/storage/storage_conflict_cleanup.dart`.
- Habit conflicts: habit payloads use their own oplog family and stay pending
  until the server declares the habits capabilities; identical habit content
  after ignoring sync metadata is not a conflict
  (`lib/features/habits/services/habit_sync_conflict_service.dart`,
  `lib/services/sync_capability_service.dart`).
- Alibaba debug/release server: `CDT-server/debug/routes/sync.js` and
  `CDT-server/math_quiz_backend/routes/sync.js`, plus their shared helper and
  service modules in the separate checkout.
- Compatibility Worker: `math-quiz-backend/src/index.js`.

Any change needs tests for local/local and client/server races, accept-server
op-log cleanup, keep-local version bumping, team authorization, deletion,
snake/camel payload compatibility, and recurrence-series backfill.
