# Uni-Sync roadmap — archived status

The original checklist mixed shipped code with aspirational items and must not
be read as a completion report. Reconciled with the working tree: 2026-07-20.

## Implemented foundations

- Per-user SQLite, op logs, audit snapshots and incremental HTTP synchronization.
- UUID/version/timestamp/device metadata across core sync entities.
- Conflict flags/snapshots, conflict inbox, local/server selection, history and
  rollback routes.
- Team membership, invitations/requests, announcements and share flows in the
  current Alibaba server.
- FTS5→FTS4→LIKE search fallback.
- WebSocket notifications for live collaboration and Pomodoro awareness.
- Rate limiting and authenticated server routes.

## Partial or different from the old design

- Conflict merge is entity/field specific, not a universal generic Diff Engine.
- Audit capture is explicit in client/server save paths, not a global
  `withAudit` hook over every write.
- Time rendering uses normal UTC/local conversions; there is no location-driven
  `DateTimeTransformer` contract.
- Search entity coverage and sync UX differ by screen and platform.

## Not evidenced in current code

- A Proof-of-Work validator for rollback/bulk writes.
- Universal snapshot preview and atomic bulk time-window rollback.
- A formal path-discovery network diagnostic pipeline.
- A guarantee that every high-risk audit record is permanently archived offsite.

Future work should be tracked in issues with tests and acceptance criteria,
rather than marking the original aspirational checklist complete.
