# 长期待办规划块当前说明

最后更新：`2026-05-24`

## 背景

长期待办不应该靠创建一堆重复待办来表达执行计划。比如“写论文”应始终是一个长期待办，而“今天 15:00-17:00 写论文”“明天 09:00-10:00 写论文”应当是挂在这个待办下面的多个规划块。

规划块承担“某个待办在某段时间执行”的职责：

- 一个长期待办可以被安排到多个具体时间段。
- 到点提醒用户开始专注。
- 番茄钟记录实际专注时长。
- 统计计划时长、实际专注时长和达成率。
- AI 可以根据课程、已有待办、已有规划和番茄记录安排时间。

## 当前核心模型

### TodoItem

`TodoItem` 继续表示任务本体，例如“写论文”“复习高数”“背英语单词”。不要用 `TodoItem.createdDate` / `TodoItem.dueDate` 反复覆盖长期待办的多个执行时间；它们更适合表达单次待办。

### TodoPlanBlock

`TodoPlanBlock` 已在 `lib/models.dart` 落地，用来表示一次具体安排。当前关键字段包括：

- `id` / `uuid`：全局唯一 ID。
- `todoId`：关联的 `TodoItem.id`。
- `titleSnapshot`：待办标题快照，便于离线显示和历史统计。
- `startTime` / `endTime`：开始和结束时间，UTC 毫秒。
- `plannedMinutes`：计划分钟数。
- `status`：`planned`、`reminded`、`focusing`、`finished`、`missed`、`skipped`。
- `actualFocusSeconds`：实际专注秒数。
- `pomodoroRecordIds`：关联番茄钟记录 ID 列表。
- `source`：来源，例如手动、AI、课程映射等。
- `remark`：规划备注。
- `reminderMinutes`：提前提醒分钟数。
- `pomodoroMinutes` / `pomodoroRounds`：番茄钟配置。
- `isDeleted`、`version`、`createdAt`、`updatedAt`、`deviceId`：同步和审计字段。

## 当前实现位置

- `lib/models.dart`：`TodoPlanBlock`、`TodoPlanStatus`。
- `lib/storage_service.dart`：`savePlanBlocks`、`getPlanBlocks`、`getPlanBlocksByDay`、`deletePlanBlockGlobally` 和 delta sync 接入。
- `lib/services/database_helper.dart`：`todo_plan_blocks` 表结构和迁移/修复。
- `lib/screens/todo_plan_screen.dart`：日视图网格、点击/滑动创建、编辑、跳过、删除、长按移动、边缘调整。
- `lib/screens/plan_block_stats_screen.dart`：规划块统计入口。
- `lib/widgets/plan_block_today_section.dart`：首页今日规划展示。
- `lib/services/reminder_schedule_service.dart`：规划块提醒调度。
- `lib/services/pomodoro_control_service.dart` 与 `lib/services/pomodoro_service.dart`：从规划块开始专注、番茄钟结束后回写规划块。
- `lib/services/ai_action_parser.dart`、`ai_todo_action_executor.dart`、`ai_todo_context_builder.dart`：AI 规划块 action 协议和执行。

## 当前交互行为

- 日视图支持 `5 / 10 / 15 / 30` 分钟粒度切换。
- 点击空白网格可创建规划块。选择待办后会启用 AI 时长估计，并自动调整结束时间和番茄轮数。
- 滑动选择时间段可创建规划块。选择待办后不会自动套用 AI 预估时间，保留用户滑动选出的时间段。
- 已有规划块支持点击编辑、长按移动、拖拽左右边缘调整开始/结束时间。
- 底部面板支持提醒分钟、备注、番茄时长和番茄轮数配置。
- `保存并开始专注` 会绑定 `planBlockId` 并进入番茄钟。
- 番茄钟记录结束后会累计 `actualFocusSeconds`、追加 `pomodoroRecordIds`，并按达成率更新规划块状态。

## 状态流转

当前主要状态语义：

- `planned`：已计划，未开始。
- `reminded`：设计上表示已提醒；当前稳定回写仍需完善。
- `focusing`：用户从该规划块开始番茄钟。
- `finished`：实际专注达到达成阈值后自动完成。
- `missed`：结束时间已过且没有实际记录。
- `skipped`：用户主动跳过。

自动规则：

- 当前时间超过 `endTime` 且无实际专注记录时，会被标为 `missed`。
- 从规划块开始番茄钟会进入 `focusing`。
- 番茄钟结束后回写实际专注时长，并在达成阈值满足时标为 `finished`。

## 番茄钟联动

`PomodoroRecord` 已支持：

- `todoUuid`
- `todoTitle`
- `plannedDuration`
- `actualDuration`
- `planBlockId`

从规划块开始专注时：

- 预选绑定待办。
- 使用规划块的番茄配置或计划时长。
- 运行状态携带 `planBlockId`。
- 结束后新增 `PomodoroRecord` 并回写规划块：累计实际专注、追加记录 ID、更新状态。

## 存储与同步

- 本地表：`todo_plan_blocks`。
- 同步入口：`StorageService.syncData()`。
- 上传字段：通过 `todo_plan_blocks_changes` 进入 `ApiService.postDeltaSync()`。
- 规划块不进入冲突中心；当前按版本/更新时间进行合并。
- 新后端能力优先落到 `aliyun_debug/`；不要修改 `aliyun_release/`，除非明确要求。
- Web 通过 Cloudflare Zero Trust API 访问，Windows/Android 可直接访问 Alibaba Cloud HTTP 服务。

## AI 规划协议

规划块使用独立 action，避免 AI 为长期待办制造重复待办。

当前支持的规划块 action：

- `create_plan_block`
- `update_plan_block`
- `delete_plan_block`
- `reschedule_plan_blocks`
- `skip_plan_block`
- `start_plan_block_pomodoro`

示例：

```json
[
  {
    "action": "create_plan_block",
    "blocks": [
      {
        "todoId": "todo-uuid",
        "startTime": "2026-05-05 15:00",
        "dueDate": "2026-05-05 17:00",
        "reminderMinutes": 5,
        "remark": "论文初稿第一节"
      }
    ]
  }
]
```

AI 规则：

- 把已有待办安排到具体时间时，必须使用 `create_plan_block`，不要使用 `plan_todos`。
- `plan_todos` 只用于创建全新待办。
- 规划中提到的每个已有待办都应生成对应规划块，不要只生成部分时间段。
- 如果上下文提供课程、已有规划或专注记录，应避开这些已占用时间。
- 不确定待办 ID 时先追问。

## 统计

当前已有：

- 今日规划展示。
- 规划块统计入口 `PlanBlockStatsScreen`。
- 番茄钟实际专注回写。

仍需完善：

- 周/月计划 vs 实际图表。
- 按待办统计的长期专注排行。
- 漏做规划块分析。
- AI 对计划过满、长期未推进待办的建议。

## 仍需收敛的点

- 系统通知点击链路还需要稳定携带 `todoId` 和 `planBlockId` 直达番茄钟。
- `TodoPlanStatus.reminded` 的回写还需要完善。
- 规划块到系统日历事件的同步还没完整落地，模型中也没有稳定的 `calendarEventId` 字段。
- 规划块变更与协同 WebSocket 广播策略还需要继续对齐。
- 需要补充 widget 测试：点击创建启用 AI 估时、滑动创建不启用 AI 估时、拖拽改期和边缘调整。

## 最近行为修正

- 2026-05-24：滑动创建规划块时，用户选择待办不会触发 AI 预估自动覆盖时间段；点击空白处创建仍保留 AI 自动估时。
