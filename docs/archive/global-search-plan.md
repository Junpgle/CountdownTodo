# Global search plan — historical reconciliation

This began as the “Uni-Sync 4.0 Omni-Console” proposal. It is archived; current
behavior was checked on 2026-07-20.

## What shipped

- `GlobalSearchOverlay` and `SearchService` provide an application-wide search
  surface with grouped results and actions.
- SQLite probes FTS5, falls back to FTS4, and finally uses `LIKE`; Chinese
  queries also receive LIKE-based recall where useful.
- FTS triggers keep todo indexes synchronized and existing rows are imported
  when an index is created.
- `search_history` stores frequency, timestamp and time-of-day counters and is
  used by timeline/statistics code.
- Static settings and quick-action registries supplement business-data results.

## Differences from the original proposal

- FTS is not guaranteed on every platform; graceful degradation is part of the
  implementation contract.
- Coverage and click behavior vary by entity. The old scope table was an
  aspiration, not proof that every listed entity and deep link shipped.
- There is no reason to preserve old line numbers or “millisecond” performance
  promises without benchmarks on the target database/device.

## Next checks

- Add ranking and Chinese-tokenization regression tests.
- Verify each result's authorization/team scope and stale-target behavior.
- Benchmark index creation, trigger maintenance and fallback search on large
  datasets before changing ranking or schema.
