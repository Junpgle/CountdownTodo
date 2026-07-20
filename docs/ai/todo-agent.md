# AI todo agent

Last verified: 2026-07-20.

The chat screen and `LLMService` support configurable LLM providers and convert
structured assistant output into previewable actions. The transport protocol
uses `[ACTION_START]` / `[ACTION_END]` blocks; suggestions have their own
structured markers. Treat model output as untrusted input and require user
review for destructive or broad actions.

## Current action families

- Todos: create, update, complete, delete, reschedule, bulk operations,
  categorization, planning, split and merge.
- Plan blocks: create, update, delete, reschedule, skip and start.
- Time logs: create, update and delete.
- Pomodoro: start/stop and tag create/update/delete.
- Countdowns: create, update, complete and delete.
- Todo groups: create, update and delete.

`AiTodoActionType` and the parser/executor code are the source of truth for exact
names and payload fields. The UI should show parsed actions before execution,
validate IDs/timestamps/enums, and keep partial failures visible.

## Test gap

The previously documented dedicated files such as
`test/services/ai_action_parser_test.dart` are not present in the current tree.
New protocol or executor changes should add focused parser, validation,
authorization and rollback/partial-failure tests before claiming full coverage.
