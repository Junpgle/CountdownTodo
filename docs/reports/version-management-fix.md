# Todo audit/version management fix

Status: historical fix summary updated for the current code on 2026-07-20.

## Problem addressed

Audit history could report “no substantial change” or omit reminder and
recurrence changes. Some save paths also failed to await audit work, allowing
ordering or visibility problems.

## Current implementation

- Normal todo save paths await audit capture where ordering matters.
- `_recordLocalAuditOptimized` receives the pre-write row and records explicit
  INSERT/UPDATE snapshots without querying after the write.
- `_recordLocalAudit` remains for paths that need an internal lookup and performs
  material-field filtering.
- Material todo fields currently include content/title, remark,
  completion/deletion, due/target time, group/category, recurrence,
  `recurrence_series_id`, date-only flag, reminder minutes, recurrence end and
  custom interval.
- Normalization treats storage sentinels such as null/0/empty/false and
  reminder `-1` carefully so metadata-only writes do not create noisy versions.
- Local and server audit snapshots are enriched with stable identifiers and
  timestamps used by the version-history UI.

## Important caveat

The optimized recorder assumes its caller already determined that a real change
occurred. New call sites must capture the old row before mutation, await the
recorder when required, and include any new business field in comparison,
serialization, database migration, sync payload and conflict resolution.

## Verification

For each audited field, edit only that field and verify one meaningful history
entry with correct before/after values. Also verify metadata-only saves create no
entry, null/sentinel equivalence, offline→online sync, rollback, conflict
resolution and recurrence-series migration. There is no dedicated comprehensive
audit regression suite in the current tree, so these cases should be automated.
