# 当前冲突判断逻辑梳理

本文基于当前本地代码梳理 Flutter 客户端、阿里云调试后端、Cloudflare Worker 后端的冲突逻辑。

## 相关文件

- `lib/storage_service.dart`：本地数据保存、同步 payload 生成、同步结果合并、本地日程冲突扫描、冲突开关读取。
- `lib/screens/home_dashboard.dart`：首页同步后冲突弹窗、团队冲突红点。
- `lib/screens/home_settings_screen.dart`：设置页冲突检测开关状态读取与保存。
- `lib/screens/settings/widgets/preference_section.dart`：设置页“冲突检测”开关 UI。
- `lib/screens/conflict_inbox_screen.dart`：冲突中心加载、分类、展示和处理冲突。
- `lib/widgets/conflict_alert_dialog.dart`：同步后首页冲突弹窗。
- `lib/models.dart`：`TodoItem`、`TodoGroup`、`CountdownItem`、`ConflictInfo` 等冲突字段模型。
- `aliyun_debug/server.js`：阿里云后端同步、版本冲突、服务端日程冲突、冲突解决接口。
- `math-quiz-backend/src/index.js`：Cloudflare Worker 同步逻辑。
- `lib/services/pomodoro_service.dart`：番茄钟记录同步入口；当前不参与冲突计算。

## 冲突检测开关

设置项为 `StorageService.KEY_CONFLICT_DETECTION_ENABLED`，实际 key 是 `conflict_detection_enabled`。

默认值是关闭。保存逻辑按账号隔离，因为它不在 `saveAppSetting` 的全局设置例外列表里。

关闭开关后的效果：

- 本地不执行待办时间重叠扫描。
- 手动扫描冲突会清理本地日程冲突并返回 0。
- 同步完成后不会重新计算本地日程冲突。
- 阿里云返回的 `schedule_conflict` 不会被客户端持久化为本地待办冲突。
- 首页不会弹冲突弹窗。
- 首页团队按钮冲突红点不显示。
- 版本冲突不受这个开关影响。

## 本地日程冲突

本地日程冲突只发生在 `lib/storage_service.dart` 的 `_recomputeLocalTodoScheduleConflicts`。

参与对象：

- 只扫描 `TodoItem` 与 `TodoItem`。

不参与对象：

- 专注记录 / 番茄钟记录。
- 时间日志。
- 课程。
- 规划块。
- 倒计时。
- 文件夹。

扫描条件：

- `todo.isDeleted == false`
- `dueDate != null`
- `todo.isAllDay == false`
- 不是近似全天范围。
- 起止时间有效：`startMs > 0 && endMs > 0 && startMs < endMs`
- 起止时间必须在本地同一天。

起止时间来源：

- 开始：`todo.createdDate ?? todo.createdAt`
- 结束：`todo.dueDate.millisecondsSinceEpoch`

重叠判断：

```text
a.start < b.end && b.start < a.end
```

冲突写入格式：

```text
hasConflict = true
serverVersionData = {
  uuid,
  id,
  content,
  team_uuid,
  schedule_scope,
  relation_type,
  conflict_kind: "logic",
  conflict_type: "local_schedule_conflict",
  source: "local_detector",
  start_time,
  end_time,
  conflict_with: [...]
}
```

`relation_type` 的分类：

- 当前项和冲突对象一个个人、一个团队：`personal_team`
- 当前项是团队项，且冲突对象都是团队项：`team_team`
- 否则：`personal_personal`

忽略冲突：

- `ignoreLocalScheduleConflict` 会把当前项与 peers 的 pair key 存入 `ignored_schedule_conflicts_<username>`。
- 后续扫描遇到该 pair key 会跳过。
- 忽略后会清除当前项及包含当前项的 peer 冲突，再重新扫描。

上传保护：

- `_stripClientOnlyConflictForSync` 会移除 `local_schedule_conflict`，并把 `has_conflict` 置 0。
- 本地日程冲突是客户端私有逻辑，不作为服务端版本冲突 payload 上传。

## 客户端同步时如何处理冲突

入口是 `StorageService.syncData`。

上传前：

- `todos`：如果本地是版本冲突，跳过上传；如果只是本地日程冲突，会剥离冲突字段再上传。
- `todo_groups`：如果 `hasConflict == true`，跳过上传。
- `countdowns`：如果 `hasConflict == true`，跳过上传。
- `time_logs`：正常按 `updatedAt > lastSyncTime` 上传，没有冲突字段。
- `todo_plan_blocks`：正常上传，不走冲突中心逻辑。

发送成功后：

- 客户端读取服务端 `response.conflicts` 并转成 `ConflictInfo`。
- `schedule_conflict` 和 `pomodoro` 类型不会阻塞 op_log 标记为已同步。
- 其他冲突会让对应 op_log 保持未同步并标记 `sync_error = server_conflict`。

合并服务端数据：

- `todos`、`todo_groups`、`countdowns` 会合并服务端 `has_conflict` 状态。
- `time_logs` 没有客户端冲突字段。
- `todo_plan_blocks` 当前只按版本/更新时间合并，不进入冲突中心。
- `pomodoro` 标签和记录通过 `PomodoroService` 单独同步。

额外补标：

- 如果 `response.conflicts` 中有 `schedule_conflict`，且冲突检测开关开启，客户端会把它转换成本地 `local_schedule_conflict` 写入对应待办。
- 如果 `response.conflicts` 中有版本冲突，并且 `conflict_with` 是同一个 item 的服务端快照，客户端会写入对应 `TodoItem.serverVersionData`、`TodoGroup.conflictData` 或 `CountdownItem.conflictData`。
- `TimeLogs don't have hasConflict field, skip`。

## 首页冲突行为

`home_dashboard.dart` 中有两个入口：

- 团队按钮红点：只有冲突检测开关开启时才计算并展示。
- 同步后的 `ConflictAlertDialog`：只有冲突检测开关开启且 `response.conflicts` 非空时才弹。

注意：这里的开关会屏蔽首页弹窗，但不会阻止版本冲突在本地保存和在冲突中心显示。

## 冲突中心

文件：`lib/screens/conflict_inbox_screen.dart`

加载对象：

- `TodoItem.hasConflict`
- `TodoGroup.hasConflict`
- `CountdownItem.hasConflict`

过滤规则：

- 已删除项不展示。
- 全天待办不展示。
- 如果冲突对象全部是全天任务，也不展示。

分类：

- `conflict_type == local_schedule_conflict` 或 `source == local_detector`：显示为时间冲突。
- 其他冲突：显示为其他冲突/版本冲突。

解决方式：

- 对日程冲突，可保留现状，调用 `StorageService.ignoreLocalScheduleConflict`，之后不再提示这组时间重叠。
- 对版本冲突，可保留本地并调用 `resolveConflictLocally` / `ApiService.resolveConflict` 清理冲突状态并提升版本。
- 批量清理幽灵冲突时，会把 `hasConflict` 和 `conflictData/serverVersionData` 清空并持久化。

## 阿里云后端冲突逻辑

文件：`aliyun_debug/server.js`

### 服务端日程冲突

函数：`checkItemConflict(item, userId)`

当前规则：

- 无开始/结束时间：不冲突。
- 全天任务：不冲突。
- 团队记录：不由服务端判定日程冲突，直接返回 `null`。
- 个人范围内查询 `courses` 和 `todos` 的时间重叠。
- 不查询 `pomodoro_records`，因此番茄钟/专注记录不参与日程冲突。
- 不查询 `time_logs`。

触发点：

- 同步 `todos` 时调用 `checkItemConflict(t, user_id)`，命中后返回 `type: schedule_conflict`。
- 课程同步时也会调用 `checkItemConflict(c, user_id)` 并写课程 `has_conflict`，但客户端冲突中心当前不加载课程冲突。

### 版本冲突

阿里云同步中会对以下类型判定版本冲突：

- `todos`
- `countdowns`
- `todo_groups`

`todos` 版本冲突条件：

```text
client.version <= server.version
&& 数据字段存在实质差异
&& client.updated_at <= server.updated_at
```

命中后：

- 返回 `type: version_conflict`
- 服务端写 `has_conflict = 1`
- 服务端写 `conflict_data = safeSnapshotJson(existing, table)`
- 本轮不再覆盖服务端数据

`countdowns` 当前条件：

```text
client.version <= server.version
&& 数据字段存在实质差异
```

它没有像 `todos` 一样额外检查 `client.updated_at <= server.updated_at`。

`todo_groups` 当前条件：

```text
client.version <= server.version
&& 数据字段存在实质差异
&& client.updated_at <= server.updated_at
```

这是当前已修复后的逻辑。用于避免“同版本但客户端更新时间更新”的文件夹修改被误判为版本冲突。

`todo_groups` 的实质差异字段：

- `name`
- `is_deleted`
- `is_expanded`

### 不再产生冲突的类型

在阿里云同步主接口中：

- `time_logs` 不做版本冲突，只按 `version` 或 `updated_at` 新旧更新。
- `pomodoro_tags` 不做版本冲突，只按 `version` 或 `updated_at` 新旧更新。
- `pomodoro_records` 不做版本冲突，也不做日程冲突，只按 `version` 或 `updated_at` 新旧更新。
- `todo_plan_blocks` 不进入冲突中心；更新时会清 `has_conflict = 0`。

独立接口 `/api/pomodoro/tags` 和 `/api/pomodoro/records` 当前也不再把番茄标签/记录打成版本冲突，更新成功会清 `has_conflict`。

### 冲突解决接口

阿里云提供冲突解决相关接口，涉及：

- `todos`
- `countdowns`
- `todo_groups`
- `pomodoro_records`
- `pomodoro_tags`

但当前客户端冲突中心主要使用 `todos`、`countdowns`、`todo_groups`。

## Cloudflare Worker 冲突逻辑

文件：`math-quiz-backend/src/index.js`

Cloudflare Worker 的 `/api/sync` 当前没有像阿里云一样返回 `conflicts` 数组，也没有写入客户端冲突中心使用的 `has_conflict/conflict_data`。

它主要按下面规则做 LWW 更新：

```text
client.version > server.version
|| client.updated_at > server.updated_at
```

适用对象包括：

- `todos`
- `countdowns`
- `todo_groups`
- `time_logs`
- `pomodoro_tags`
- `pomodoro_records`

因此在 Cloudflare 路线下，当前同步更接近“较新版本/较新更新时间覆盖”，不会走本地冲突中心那套版本冲突展示流程。

## 专注记录 / 番茄钟 / 时间日志结论

当前代码中：

- 本地日程扫描不包含专注记录、番茄钟、时间日志。
- 阿里云 `checkItemConflict` 不查询 `pomodoro_records` 和 `time_logs`。
- 阿里云同步不再为 `pomodoro_tags`、`pomodoro_records` 生成版本冲突。
- 时间日志没有客户端 `hasConflict` 字段，也不会进入冲突中心。

所以“专注记录 / 番茄钟 / 时间日志永远不参与冲突计算”在当前主要路径上成立。

## 当前需要注意的边界

- `countdowns` 在阿里云版本冲突判断里仍未比较 `client.updated_at <= server.updated_at`，如果未来出现同版本但客户端更新时间更新的倒计时误冲突，可以按 `todo_groups` 的修复方式同步修。
- `courses` 服务端可能写 `has_conflict`，但客户端冲突中心不展示课程冲突。
- Cloudflare Worker 不返回 `conflicts`，因此服务器线路切换会影响“版本冲突是否进入冲突中心”的体验。
- 关闭冲突检测开关只关闭日程冲突和首页提醒，不关闭版本冲突的持久化。
