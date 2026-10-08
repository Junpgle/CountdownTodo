# Todo plan blocks

Last verified: 2026-10-08 (availability recommendations; existing platform integrations retain their own verification boundaries).

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

## Find available time

Click or drag to create a plan, or edit an existing plan, then open **找可用时间**
in the shared `PlanBlockEditorSheet`. Pick a date, duration (15/30/45/60 minutes
or a positive custom value), and a day window (08:00–22:00 by default).
The local engine defaults to five chronological candidates, with 3/5/8 choices
in the editor. It first covers distinct gaps, then adds later non-overlapping
alternatives inside long gaps; fewer are shown when the day cannot fit enough.
Today starts at the next valid minute; timed
and date-only todo deadlines limit candidate endings.

The snapshot checks adjusted course occurrences, fixed schedules, active plan
blocks and compatible same-day legacy execution intervals. Cross-day fixed
schedules/plans are clipped to the query date. Plan states planned/reminded/
delayed/focusing occupy time. Only planned/reminded/delayed plans can use
recommendations when editing, and only that plan UUID is excluded.

A multi-day todo deadline does not reserve every intervening hour. Zero business
start placeholders and physical creation-time fallbacks are not execution
reservations. These rules match the planning calendar's same-day legacy
projection without rewriting todo records. Other genuine same-day legacy
execution intervals remain busy and are deduplicated against existing plans.

Android/iOS device events are included only when the existing read toggle and
permission allow it. All-day and cross-date phone events are informational
all-day schedules and do not occupy availability; the original event timestamps
and half-open date overlap rules remain intact. Same-day timed events, including
instant reminders with the bridge's one-minute duration, still occupy time.
Other platforms check app schedules only. App-source
failures stop the query; a failed phone-calendar query requires explicit
**仅按应用内安排查找** to continue. Coverage, cutoff and the counted busy intervals
are visible. External titles, locations and events are never saved or logged.

Choosing a candidate only fills the draft. **保存规划** and **保存并开始专注** recheck
current account/todo, sources and time; phone events bypass the old session
cache. A conditional SQLite transaction rechecks the latest local occupancy
and plan version before writing the plan and its existing oplog. Editable fields
change on a copy; actual-focus, linked-record, calendar and sync metadata stay
intact. A conflict or read failure retains the draft and does not start focus.

Input changes, related refreshes, calendar setting changes and foreground
resume invalidate recommendations. Request/estimate sequence guards discard
old responses. Repeated clicks cannot create duplicate plans; failed focus
startup retries the saved plan, and a successful startup followed by a failed
status write retries only the status. Native startup failures after a run marker
is persisted are recognized before retrying.

This is a local recommendation, not an atomic cross-device/system-calendar
reservation. Manual dragging/resizing, AI batch planning and global sync keep
their existing paths. No database schema, backend protocol or native permission
was added.


## Flexible planning settings and actual execution

Single-round Pomodoro duration, round count and advance reminders are arranged
in three columns on wide sheets, two on mobile, and one only where the width
cannot fit two. The additional AI planning button has been removed from this
editor. The day planning timeline retains all 24 hours in one screen with its
existing click/drag creation gesture; no scrolling container was added.

Optional avoidance preferences include lunch rest (12:00–14:00), lunch
(11:30–12:30), and dinner (18:00–19:00). Each can be enabled separately, its
start/end changed, or supplemented by removable custom daily ranges. They
start disabled. Overlapping preferences are merged with busy intervals for
calculation; they also constrain the final save check. Changing a preference
or candidate count invalidates previously selected recommendations. These are
current-editor preferences, not persisted calendar events.

The planning screen displays focus records and time logs in separate read-only
lanes beneath each hour's plan lane. Its legend shows daily record counts and
opens a lazy record list; entries navigate to the existing focus/log detail
screens. Records overlapping midnight are clipped for the timeline but retain
their original dates in details. Focus's effective duration remains separate
from its wall-clock span. Logs do not count toward a plan's completed focus.
The day query uses account-scoped SQL ranges with existing legacy migrations;
local saves emit the corresponding refresh signal. Viewing/dragging actual
records never creates or edits a planning block.
