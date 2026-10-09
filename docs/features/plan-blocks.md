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
- New blocks only offer undeleted, unfinished todos. Filtering happens before
  recurrence-series collapse so a completed occurrence cannot hide an unfinished
  one. With no eligible todo, the editor shows an empty state and disables save
  and focus. A refreshed invalid selection requires explicit reselection.
- Existing blocks retain their linked todo for display; completed linked todos
  are disabled menu entries, and other completed todos are excluded. New or
  relinked manual plans recheck the todo in the write transaction, rejecting
  completion/deletion after the editor opened without writing a plan or oplog.
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

## Create a plan from todo editing

From the homepage's todo editor, **计划安排 → 新建规划块** opens the shared
full-page editor for that exact unfinished todo. The existing **今日计划** link
remains.
It first runs the existing completion-time prediction, then restores account-local
avoidance and searches for that predicted duration. No fixed-duration search
runs before prediction completes. The first valid suggestion fills the draft;
two recommendations are visible immediately. **自定义寻找时段** opens a bounded
dialog with date, duration, window, avoidance and 3/5/8 candidate controls (five
by default). Select a result to return to the page; a custom selection remains
visible even when it was outside the original first two. The predicted duration
is shown as **预计用时** and can be adjusted.

Prediction/search only fill the draft; saving remains explicit and uses the
existing fresh occupancy checks. User edits or closing the page invalidate late
automatic selection. Prediction failure asks for manual duration instead of
silently searching a fixed duration. Empty results and calendar failures remain
visible, with the existing explicit app-only fallback. Day-grid click/drag and
missed-plan recovery retain their existing initialization behavior.

## Find available time

Homepage todo creation, day-grid click/drag and missed-plan recovery push a
standard page route with a back button. Its recommendation area automatically
shows up to two available slots and a **自定义寻找时段** entry, without an inline
search form. Search criteria and additional results live in the dialog; choosing
a result fills the draft and closes the dialog. Cancel preserves the current
selection. Reopening restores the current query and the account's avoidance
preferences. Changing availability invalidates old candidates; saving still
rechecks the latest data. Drag-created drafts keep their selected time until the
user chooses a suggestion.

Existing-plan editing keeps its bounded sheet and **找可用时间** panel. Pick a date,
duration (15/30/45/60 minutes or a positive custom value), and a day window
(08:00–22:00 by default).
The panel expands and collapses over 260 ms with a top-aligned height transition,
a content crossfade, and a rotating arrow. Rapid toggles retain the duration and
query settings. The system's reduce-motion setting switches the content
immediately.
The local engine defaults to five chronological candidates, with 3/5/8 choices
in the custom search dialog (or existing-plan editor). It first covers distinct
gaps, then adds later non-overlapping alternatives inside long gaps; fewer are shown when the day cannot fit enough.
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
in three columns on wide editors, two on mobile, and one only where the width
cannot fit two. The additional AI planning button has been removed from this
editor. The day planning timeline retains all 24 hours in one screen with its
existing click/drag creation gesture; no scrolling container was added.

Optional avoidance preferences include lunch rest (12:00–14:00), lunch
(11:30–12:30), and dinner (18:00–19:00). Each can be enabled separately, its
start/end changed, or supplemented by removable custom daily ranges. They
start disabled on first use. Selection, edited preset times, and custom ranges
are remembered locally per account as soon as they change, including deselection
and removal, and restored on the next editor opening even when no plan was saved.
Account switches reload that account's preferences. Lookup waits for restoration;
the restored query also reaches the manual-save check. Overlapping preferences
are merged with busy intervals for calculation; they also constrain the final
save check. Changing a preference or candidate count invalidates previously
selected recommendations. These are search defaults, not calendar events.

The planning screen displays focus records and time logs in separate read-only
lanes beneath each hour's plan lane. Its legend shows daily record counts and
opens a lazy record list; entries navigate to the existing focus/log detail
screens. Records overlapping midnight are clipped for the timeline but retain
their original dates in details. Focus's effective duration remains separate
from its wall-clock span. Logs do not count toward a plan's completed focus.
The day query uses account-scoped SQL ranges with existing legacy migrations;
local saves emit the corresponding refresh signal. Viewing/dragging actual
records never creates or edits a planning block.

## 漏做规划重新安排（2026-10-09）

首页今日规划展开漏做行、统计漏做行以及日视图漏做编辑器均提供“重新安排”。统计超过十项可查看当前范围的全部漏做；虚拟课程与旧待办映射不会转换为可恢复规划。

重新安排锁定原具体待办，显示原日期和时段，默认展开当天查找，保留今天／明天快捷选择、五个候选与可编辑避让。带入原有效计划时长、备注、提醒、番茄配置；无效旧配置使用支持的默认值并提示。实际投入不会被当作剩余工作量。

显式保存只新建一条 manual／planned 规划，采用新UUID、零实际专注，不继承旧日历或番茄记录身份。原漏做行、计数、待办完成与重复规则保持，取消零写入。手动改时间仍检查真实占用、截止及当前避让。手机日历失败只有明确选择应用内模式才降级。

已有后续安排先展示，可查看已有规划或明确再新建；正在专注时仅查看当前专注。保存前新增或变动的后续安排要求重新核对，保留输入。原来源变更、待办完成／删除／冲突、账号切换、占用或截止失效都阻止保存。新规划和oplog同一事务，再次校验后写入；连击与专注重试复用新规划身份。

验收证据见[第三轮验收报告](../reports/2026-10-09-missed-plan-recovery-acceptance.md)。
