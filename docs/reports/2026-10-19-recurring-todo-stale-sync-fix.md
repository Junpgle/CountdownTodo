# 循环待办旧数据覆盖修复记录

日期：2026-10-19。状态：客户端、开发服务端和正式服务端代码已修复；未打包、部署或进行真实双设备验收。

## 修复结果

已封住排查时复现的三个入口：自动循环维护重新刷新旧内容的时间戳、本地旧列表覆盖较新 SQLite 记录、同步落库只保住完成值却回退日期和版本。

| 场景 | 本次结果 |
| --- | --- |
| 旧设备跨日自动滚动后上传旧未完成状态 | 自动维护保留原修改时间；服务端核对维护基线，基线已过期则保留服务端内容并返回当前记录 |
| 旧设备缺少服务器已经完成的实例，重新补生成 | 以仅插入操作上传，不能覆盖已存在实例 |
| 读取旧列表后，本地已保存较新的完成状态/日期 | 事务内比较数据库当前版本，拒绝旧行，也不会生成旧内容的 oplog |
| 同步请求或最终落库期间出现新操作 | 保护整条待办、业务日期和版本元数据；新操作保留待上传 |
| 去重时向标准实例转移完成状态失败 | 保留仍承载完成状态的重复实例，避免先删除副本造成丢失；已覆盖两种请求排列顺序 |
| 循环结束日期已在另一端延长，旧规则仍尝试删除实例 | 维护载荷携带规则基线，服务端拒绝过期规则的删除 |
| 用户主动取消完成或主动合并系列 | 继续按真实用户编辑推进时间戳，保留原有操作能力 |

## 实现范围

### Flutter

- `lib/models.dart`：增加自动维护专用的版本推进方法，保持原 `updatedAt`。用户编辑仍调用原来的 `markAsChanged`。
- `lib/storage_service_todos.dart`：批量保存和单条更新统一走事务，事务内读取当前记录、检查新旧及维护基线、写入记录/独立完成状态/同步日志。跳过旧数据后不再产生旧内容的日志或独立完成写入。
- 自动循环只保存实际变化的记录。补生成实例沿用源记录的时间戳，维护操作带 `_recurrence_maintenance` 基线与仅插入标记。本地循环规则在读取后已改变时，跳过由该旧规则派生的保存，重新读取已提交状态。
- `lib/storage_service_sync.dart`、`lib/storage_service_conflict.dart`：系列修复、去重、截止边界修复和迁移冲突清理不再伪装成当前用户编辑。同步修复分别保留本地落库基线和原始服务端基线，批量回读后检查再排队。
- `lib/services/sync_oplog_policy.dart`：待上传的用户操作优先于后来产生的自动维护；增量兜底不再用更早读取的模型覆盖已选中的操作载荷。日志时间相同时使用操作 ID 保证顺序。
- `lib/services/api_service.dart`：保留服务端拒绝维护的 UUID 列表，使客户端能接受对应的服务端当前记录；仍保护请求期间新产生的用户操作。
- `lib/services/database_helper.dart`：相关读取和审计方法允许使用事务执行器，同时保留大文本分块读取。
- `.gitignore`：仅增加新回归测试文件的跟踪例外。

### CDT-server

服务端修复先落在 `debug/`，随后按用户要求同步到 `math_quiz_backend/`：

- `debug/services/recurringTodoOccurrence.js`：验证维护的版本/修改时间基线、仅插入标记及关联循环规则基线；兼容历史字符串时间戳。
- `debug/routes/sync.js`：拒绝过期维护后返回全量当前记录和 `todo_maintenance_rejected_uuids`。维护不写入独立个人完成状态；去重转移失败时保留完成副本。
- `debug/services/recurringTodoSyncRoute.test.js`：使用服务端现有 `sqlite3` 驱动、内存数据库和真实路由 handler 验证，不打开应用数据库或监听网络端口。
- `math_quiz_backend/services/recurringTodoOccurrence.js`、`math_quiz_backend/routes/sync.js`：同步相同的基线校验、去重保护和拒绝 UUID 响应逻辑。

工作区另有其他并行任务的改动，本轮未回退、格式化、提交或包含那些文件。

## 验证

新增 Flutter 回归最初的三个核心用例在修复前均失败，修复后通过。新文件共 11 项，覆盖真实 SQLite、并发保存、独立完成保护、正常取消完成，以及通过回环 HTTP 验证 API 解析和连续两轮客户端同步。

以下关联 Flutter 测试共 **133 项通过**：

```bash
flutter test --no-pub \
  test/services/todo_recurrence_sync_regression_test.dart \
  test/services/todo_lww_service_test.dart \
  test/services/sync_oplog_policy_test.dart \
  test/models/todo_recurrence_series_test.dart \
  test/models/todo_time_semantics_test.dart \
  test/services/schedule_conflict_service_test.dart \
  test/services/storage_service_history_test.dart \
  test/services/user_session_storage_test.dart \
  test/services/plan_cleanup_repository_test.dart \
  test/widgets/todo_recurrence_completion_overview_test.dart \
  test/widgets/todo_recurrence_occurrence_picker_test.dart \
  test/widgets/todo_recurrence_progress_test.dart --reporter expanded
```

服务端共 **17 项通过**（8 项既有测试、9 项新增测试）：

```bash
# 在 CDT-server 根目录；复用已有依赖，不安装或改写正式服务端文件。
NODE_PATH=/Users/junpgle/WebstormProjects/CDT-server/math_quiz_backend/node_modules \
  node --test debug/services/recurringTodoSyncRoute.test.js \
  debug/services/todoLww.test.js debug/services/recurringTodoOccurrence.test.js
```

本次涉及的 10 个 Dart 文件定向 `flutter analyze --no-pub` 通过，无问题；两个仓库本次改动路径的 `git diff --check` 通过。未运行全项目 analyze、全量测试或安装包构建。

正式服务端代码同步后，`node --check` 对上述两个正式文件通过，正式文件 `git diff --check` 通过。本轮没有重跑自动化测试；新增的真实路由集成测试仍位于 `debug/`，正式路由尚未单独做集成测试。

自动化验证使用合成数据。Flutter 同步链使用回环 HTTP 响应，服务端测试直接执行真实路由；没有连接真实账号或线上服务，不能据此宣称已完成真实多端联调或设备验收。

## 生效边界

完整保护需要发布修复后的客户端，并将正式服务端同步改动按正常流程部署。尚未升级、且不携带维护标记的旧客户端继续走兼容写入逻辑；不能宣称只升级服务端就能识别所有历史客户端的自动操作。

已被旧数据覆盖的历史状态没有自动重建。本轮未提交、推送、修改版本号、生成安装包、变更线上数据库或部署服务。
