# 待办助手 AI Agent 改造记录

## 改造目标

本次对话围绕“让大模型赋能整个待办应用”展开，将原本偏聊天式的待办助手升级为可理解应用上下文、生成结构化操作、由用户确认后执行的应用级 AI Agent。

## 核心能力

- 支持待办创建、修改、完成、删除、改期、批量改期、分类整理、规划、拆分、合并。
- 支持规划块操作：创建、更新、删除、重排、跳过、从规划块开始番茄钟。
- 支持待办分类/文件夹的新增、改名、删除，并兼容 `create_todo_group`、`create_group`、`create_category`、`create_folder` 等模型常见 action 命名。
- 支持读取当前待办、分类、课程表、专注记录、同步冲突、团队信息、倒计时、番茄标签等上下文。
- 支持 AI 返回 `[ACTION_START]...[ACTION_END]` 结构化操作块，由客户端解析、展示、确认、执行。
- 支持 AI 返回 `[SUGGEST_START]...[SUGGEST_END]` 后续建议，用于快速追问。
- 对删除、完成、合并删源、拆分删源、停止番茄钟、删除记录等危险操作增加确认提示。
- 将聊天请求、上下文构建、动作解析、动作执行拆成独立服务，降低 `TodoChatScreen` 的职责。

## 主要文件变更

- `lib/models/ai_todo_action.dart`
  - 新增 AI 待办动作模型。
  - 支持 `create_todo`、`update_todo`、`complete_todo`、`delete_todo`、`reschedule_todo`、`bulk_reschedule`、`categorize_todo`、`plan_todos`、`split_todo`、`merge_todos` 等动作。
  - 保留旧 JSON 结构兼容。

- `lib/models/chat_message.dart`
  - 将聊天消息里的待办动作从原始 Map 升级为 `AiTodoAction`。
  - 支持历史消息反序列化兼容。

- `lib/services/ai_action_parser.dart`
  - 新增 AI 操作块解析器。
  - 负责提取操作、建议、清理展示文本。
  - 支持拆分任务自动生成子任务，合并任务自动生成新任务和可选删除源任务。
  - 支持 `create_plan_block`、`update_plan_block`、`delete_plan_block`、`reschedule_plan_blocks`、`skip_plan_block`、`start_plan_block_pomodoro`。

- `lib/services/ai_todo_action_executor.dart`
  - 新增动作执行器。
  - 将已确认的 AI 动作转换为新增待办和更新待办。
  - 保留已有任务的分类、时间、提醒等信息，避免不必要覆盖。

- `lib/services/ai_todo_context_builder.dart`
  - 新增系统提示词和上下文构建器。
  - 统一注入待办、分类、倒计时、番茄标签和按需上下文。
  - 增加时间规则：所有上下文时间按本地 `yyyy-MM-dd HH:mm` 解释，并以当前基准时间和时区判断今天、昨天、明天。
  - 专注记录上下文支持按“今天/昨天/本周/本月”在客户端预先筛选和汇总，避免模型把昨日记录误判为今日记录。
  - 专注统计上下文已合并补录 `TimeLogItem` 和番茄钟 `PomodoroRecord`，会分别给出补录、番茄钟和总计时长。
  - 规划规则已明确区分 `plan_todos` 和 `create_plan_block`：创建全新待办才使用 `plan_todos`，把已有待办安排到具体时间必须使用 `create_plan_block`。
  - 当上下文包含课程、已有规划块或专注记录时，模型需要避开已占用时间。

- `lib/services/ai_chat_service.dart`
  - 新增通用 AI 聊天服务。
  - 统一处理 HTTP 请求、SSE 流式响应、思考内容、非流式标题生成。

- `lib/services/ai_todo_chat_launcher.dart`
  - 新增统一入口。
  - 各业务页面通过该服务打开待办助手并传入上下文。
  - 修正时间传递：待办时间不再输出 ISO/UTC 风格字符串，改为本地 `yyyy-MM-dd HH:mm`，避免昨天被模型误判为今天。

- `lib/screens/todo_chat_screen.dart`
  - 改为使用新的上下文构建、聊天服务、动作解析和动作执行服务。
  - 扩展 AI 操作卡片，展示新增、完成、删除、改期、批量改期、修改、整理、规划、拆分、合并等动作。
  - 增加变更摘要和危险操作提示。

## 已接入的入口

- 首页待办区：可基于当前待办、分类、冲突、课程、专注记录、团队信息提供建议和操作。
- 课程页面：可从课程表视角创建学习计划、安排复习和待办。
- 专注记录页面：可分析专注记录并创建后续待办或安排番茄钟相关计划。
- 冲突收件箱：可辅助理解同步冲突并生成待办调整建议。
- 团队管理页面：可基于团队上下文整理协作任务。
- 待办规划页：AI 可以创建/调整规划块，规划块仍绑定已有待办，避免重复制造长期待办。

以上入口均已接入番茄钟记录上下文；首页入口还会在 AI 新增/修改/删除分类后刷新分类列表。

## 当前规划块交互约束

- 用户通过点击空白时间格创建规划块时，选择待办后允许 AI 时长估计自动调整结束时间和番茄轮数。
- 用户通过滑动选择时间段创建规划块时，选择待办后不启用 AI 自动填时，避免覆盖用户手动选择的时间段。
- AI 生成规划时必须优先绑定已有待办 ID；只有用户明确要求创建新待办时才使用 `plan_todos`。

## 测试覆盖

- `test/services/ai_action_parser_test.dart`
  - 覆盖多动作解析、旧格式兼容、规划块、拆分、合并、批量改期。

- `test/services/ai_todo_action_executor_test.dart`
  - 覆盖新增、完成、分类清空、忽略未选动作、规划块/拆分创建、批量改期保留分类。

- `test/services/ai_todo_context_builder_test.dart`
  - 覆盖系统提示词、动作协议、按关键词注入课程/专注/冲突/团队上下文。
  - 覆盖“今天专注了多久”场景，确认昨日 22:15 的记录不会计入今日，今日 10:47 的 1 小时 28 分钟会被正确汇总。
  - 覆盖补录记录和番茄钟记录合并统计，确认今日合计会同时包含两类记录。

- `test/services/ai_action_parser_test.dart`
  - 覆盖待办分类 action 别名解析。

- `test/services/ai_todo_action_executor_test.dart`
  - 覆盖待办分类新增、改名、删除的执行结果。

- `test/services/ai_todo_chat_launcher_test.dart`
  - 覆盖入口待办转换，确认删除态过滤、完成态保留、本地时间格式输出。

## 已验证命令

- `flutter test test\services\ai_action_parser_test.dart test\services\ai_todo_action_executor_test.dart test\services\ai_todo_context_builder_test.dart`
- AI 核心文件曾通过定向 `dart analyze`，未发现问题。

## 已知注意事项

- 大页面如 `home_dashboard.dart`、`todo_section_widget.dart`、`course_screens.dart`、`time_log_screen.dart`、`conflict_inbox_screen.dart`、`team_management_screen.dart` 仍存在一些历史 lint/warning，本次没有做无关清理。
- 本地 `dart format` 可能因为用户目录下 Dart telemetry 文件权限返回非零退出码，但目标 Dart 文件已完成格式化。

## 最近更新

- 2026-05-24：补充规划块 action 当前状态和点击/滑动创建时 AI 自动估时差异。
