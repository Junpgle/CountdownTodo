# AI todo agent

Last verified: 2026-07-31.

The chat screen and `LLMService` support configurable LLM providers and convert
structured assistant output into previewable actions. The transport protocol
uses `[ACTION_START]` / `[ACTION_END]` blocks; suggestions have their own
structured markers. Treat model output as untrusted input and require user
review for destructive or broad actions.

## Current action families

- Todos: create, update, complete, delete, reschedule, bulk operations,
  categorization, planning, split and merge.
- Fixed schedules: create, update, cancel and delete, including
  occurrence-only and current-and-future recurrence scopes.
- Plan blocks: create, update, delete, reschedule, skip and start.
- Time logs: create, update and delete.
- Pomodoro: start/stop and tag create/update/delete.
- Countdowns: create, update, complete and delete.
- Todo groups: create, update and delete.

`AiTodoActionType` and the parser/executor code are the source of truth for exact
names and payload fields. The UI should show parsed actions before execution,
validate IDs/timestamps/enums, and keep partial failures visible.

Recurring todos and schedules use real occurrence IDs for mutations. Series IDs
are validation/grouping metadata and must never be used in place of `todoId` or
`scheduleId`. Completion is todo-only and always applies to one occurrence;
schedule cancellation is a separate status transition.

## Test coverage

`test/services/ai_todo_recurrence_alignment_test.dart` covers recurring todo
scope, fixed-schedule parsing/execution and planning context. New protocol or
executor changes should continue to add focused parser, validation,
authorization and rollback/partial-failure tests.
