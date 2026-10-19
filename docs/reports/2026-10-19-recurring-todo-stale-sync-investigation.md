# 循环待办多端旧数据覆盖复查

日期：2026-10-19。状态：已复现并定位，尚未修改功能代码。

后续：用户批准后已完成客户端和开发服务端修复，见 [修复验收记录](2026-10-19-recurring-todo-stale-sync-fix.md)。本文保留排查时的原始结论与实验结果。

本次反馈是“已完成状态回退，或下一次待办恢复成旧日期”。排查范围为当前 Flutter 源码、本地 CDT-server 同步源码、隔离 SQLite 数据库及真实 `/api/sync` 路由。未读取真实账号数据，未连接线上服务器，未核对设备版本或线上部署版本，因此下面证明的是当前代码存在可产生该现象的路径，尚不能逐条对应实际事故日志。

## 结论

上次的严格 LWW（修改时间优先、版本号仅用于同时间决胜）仍有效，但输入端会把旧内容重新标成新修改；本地落库端也存在绕过 LWW 的整行替换。仅继续调整同步比较器无法封住这些入口。

### 1. 自动循环滚动把旧状态重新变成“最新写入”

- `lib/storage_service_sync.dart:708`：同步上传之前先调用 `getTodos`。
- `lib/storage_service_todos.dart:1730`：读取待办会执行 `_handleRecurrenceLogic`。
- `lib/storage_service_todos.dart:2094`：旧循环锚点在滚动后清除 `recurrence`。
- `lib/storage_service_todos.dart:2107`：对原实例调用 `markAsChanged`，整条记录的 `updatedAt` 变成当前时间。该实例保留的是旧设备自己的完成状态、时间等字段。
- `lib/storage_service_todos.dart:2159`：整批保存并生成待上传操作。
- `CDT-server/debug/routes/sync.js:395`、`:451`：服务端根据新的时间戳接受整行更新，包括 `is_completed`、`due_date` 和 `created_date`。

因此，设备 A 完成任务后，仍持有旧未完成副本的设备 B 在跨日启动或重新读取列表时，可以只因为自动循环维护而获得更新的时间戳，并把 A 的完成和时间修改覆盖。B 不需要主动取消完成。

**完整复现实验：** Flutter 真实存储方法生成上传载荷，再交给 Node 中真实同步路由与内存 SQLite。

| 输入 | 服务端结果 |
| --- | --- |
| 原始旧快照，版本 2、时间较早 | 拒绝；已完成和较新的截止时间保留 |
| 同一旧快照经过客户端自动循环滚动，版本 3、时间变成当前 | 接受；服务端版本 4 的已完成被改回未完成，截止时间从 13:00 回退到 10:00 |
| 上述覆盖后的冲突列表 | 空数组，没有冲突提示 |

时间示例来自合成数据，不是用户任务。

### 2. 本地旧列表可以整批覆盖更新后的 SQLite

`saveTodos` 在 `lib/storage_service_todos.dart:244` 起对比差异并创建 oplog，但不会先拒绝比数据库旧的记录；`:319` 起使用整行 `INSERT OR REPLACE`。入口的 LWW 只对传入列表内的同 UUID 副本去重，不与 SQLite 当前行比较。

循环处理一旦有 `needSave`，`:2159` 会保存整个读取列表，包含本次完全没有修改的其他待办。因此读列表、用户操作、同步写入之间存在交错时，早先读取的列表可以把后来保存的内容写回去，并再生成旧内容的上传操作。

**SQLite 复现实验：** 读取旧列表 → 保存较新的已完成/13:00记录 → 再保存旧列表。结果为完成 `1 → 0`、截止 `13:00 → 10:00`，`updated_at` 也回退到旧值。

此实验确定性验证了保存入口的行为；没有将它宣称为整套 UI 并发时序的设备实测。

### 3. 同步落库的最终保护仅保留完成值

`lib/storage_service_todos.dart:303` 的保护在存在待同步 oplog 时只保留 `is_completed`；后续仍用旧快照替换 `due_date`、`created_date`、`version`、`updated_at`、循环字段等。

**SQLite 复现实验：** 保留一条较新本地操作后写入旧同步快照，完成值仍为 `1`，但截止时间退回旧值，版本 `4 → 2`。主同步流程已在响应后回读请求期间变更过的记录，这能缩小风险；最终落库边界仍缺少完整记录保护，不能仅靠内存 UUID 集合或完成值保护保证一致性。

### 同类待修入口

`lib/storage_service_sync.dart:2669` 会给修复系列关系/去重后的记录统一 `markAsChanged`，可能再次刷新本应保留的获胜副本时间戳。`_copyForNextRecurrence` 创建新实例时也使用当前创建时间和默认未完成状态；旧设备缺失服务器已存在实例时，需要明确区分“自动补生成”和“用户修改”。这些应与上述自动维护写入语义一并审计，本次未声称逐个完成端到端复现。

## 为什么已有回归没有发现

现有测试主要覆盖“旧时间戳不能靠高版本获胜”、oplog 请求快照边界、纯循环日期/去重算法；缺少“旧副本先执行真实自动滚动，再上传到已有较新完成记录”的组合场景，也缺少旧整批快照与较新 SQLite 写入之间的落库验证。

## 建议修复范围与验收

1. **区分用户操作与自动维护。** 循环锚点转移、系列关系修复、重复实例整理只更新它们负责的字段；不能把旧完成状态和业务时间随着新的维护时间整行上传。自动补生成实例遇到服务器已有同一实例时，应取回已有状态，不能按新建副本的默认未完成覆盖。
2. **本地保存增加事务内保护。** 自动处理只保存确实变更的记录；最终写入按事务中的当前 SQLite 行和操作基线检查版本，避免检查与写入之间再次被插入其他操作。请求期间或落库前新增的操作须保护完整记录及其待上传日志。
3. **服务端增加相应写入语义和基线校验。** 正常开发只修改 `CDT-server/debug/`；部署、正式树同步另行处理。须设计旧客户端兼容策略：旧客户端不提供维护标记/编辑基线时，单靠整行时间戳无法可靠区分自动滚动和真实取消完成。
4. **保留合法取消完成。** 不能简单把完成状态改成单向不可回退，也不能一概拒绝所有低版本但新时间戳的用户操作。

验收应至少包含：A 完成、B 离线跨日后恢复同步；A 修改时间、B 自动滚动；请求期间完成/取消完成；读旧列表后保存新状态再执行自动维护；同 UUID 旧设备补生成；系列去重/关系修复；正常用户取消完成。每个场景继续执行两轮干净同步，检查数据库内容和待上传日志均不反复回退。设备验收应使用实际涉及的平台组合。

## 已执行验证

```bash
flutter test --no-pub test/services/todo_lww_service_test.dart test/services/sync_oplog_policy_test.dart test/models/todo_recurrence_series_test.dart --reporter expanded

NODE_PATH=/Users/junpgle/WebstormProjects/CDT-server/math_quiz_backend/node_modules node --test debug/services/todoLww.test.js debug/services/recurringTodoOccurrence.test.js
```

- Flutter 既有相关用例：49 项通过。
- 服务端既有相关用例：8 项通过。
- 临时 Flutter SQLite 诊断实验：3 项均复现预期缺陷。实验断言的是缺陷存在，不能视为功能验收通过。
- Node 真实路由诊断实验：确认原旧快照被拒绝、自动滚动后的旧快照被接受，造成完成与时间回退。
- Flutter 实验中自动排队的 HTTP 被测试框架拦截，没有访问线上；Node 路由实验直接调用 handler，没有绑定网络端口。
- 本地服务端 `debug/routes/sync.js` 与正式目录对应文件在本次相关逻辑上相同，差异仅为缩进；没有修改正式目录，也不据此推断线上已部署版本。
- 未运行全项目 analyze、全量测试、安装包构建或双设备实测；本轮没有功能代码变更。

临时证据文件（系统临时目录可能被清理）：

- `/private/tmp/countdown-recurring-stale-snapshot-probe_test.dart`：Flutter 诊断实验源代码；放回项目测试目录即可按普通 Flutter test 运行。
- `/private/tmp/countdown-recurring-rollover-probe.json`：Flutter 自动滚动前后的合成载荷。
- `/private/tmp/countdown-recurring-route-probe.cjs`：直接调用当前 debug 同步路由的隔离脚本。
- `/private/tmp/countdown-recurring-route-probe-result.json`：路由实验结构化结果。
- `/private/tmp/countdown-recurring-route-probe.log`：路由实验日志。

仅新增本报告。临时探针已从项目测试目录移出；未提交、推送、部署或改写真实数据。
