# Todo plan blocks

Last verified: 2026-08-25.

A todo describes an outcome and due semantics; a `TodoPlanBlock` describes a
scheduled execution window. Multiple blocks may point to one todo.

## Model

- Status: `planned`, `finished`, `delayed`, `cancelled`, `reminded`, `focusing`,
  `missed`, or `skipped`.
- Source: `manual`, `ai`, or `calendar`.
- Tracks start/end, planned minutes, actual focus seconds, linked Pomodoro record
  IDs, reminder minutes, Pomodoro configuration, version/sync metadata and an
  optional `calendarEventId`.

## Behavior

- Users can create blocks by clicking/dragging, move them by long press and
  resize their horizontal edges.
- Reminder choices currently include 0, 5, 10, 15 and 30 minutes. Scheduling
  moves eligible planned/reminded blocks into the reminded state.
- Starting focus sets focusing; Pomodoro linkage updates actual focus, and the
  current completion rule can mark a block finished at 80% of planned duration.
- Calendar sync creates/updates events and persists the external event ID so
  later updates or deletion target the same event.
- Statistics include planned versus actual time, completion/missed metrics,
  per-todo summaries and recommendation text.
- AI actions can create, update, delete, reschedule, skip and start plan blocks.

Plan blocks do not turn a todo's date-only/deadline field into an execution
interval. See `todo-semantics.md` for the product distinction.
