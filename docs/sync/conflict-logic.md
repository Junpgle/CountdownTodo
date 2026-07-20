# Current conflict logic

Last verified against the Flutter client and external Alibaba debug server:
2026-07-20.

## Two conflict classes

### Version conflicts

The server compares a submitted object with the stored UUID/version/timestamps
and business fields. When a stale/equal-version payload differs and is not a
safe migration, it marks the server object with `has_conflict`, stores
`conflict_data`, and returns a `version_conflict`. These conflicts are not
disabled by the schedule-detection setting.

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

## Source map

- Client: `lib/storage_service.dart`, `lib/screens/conflict_inbox_screen.dart`,
  `lib/models.dart`, `lib/services/storage/storage_conflict_cleanup.dart`.
- Alibaba debug server: `CDT-server/debug/routes/sync.js`,
  `routes/other.js`, and `services/syncHelper.js` in the separate checkout.
- Compatibility Worker: `math-quiz-backend/src/index.js`.

Any change needs tests for local/local and client/server races, accept-server
op-log cleanup, keep-local version bumping, team authorization, deletion,
snake/camel payload compatibility, and recurrence-series backfill.
