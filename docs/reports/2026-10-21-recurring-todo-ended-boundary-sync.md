# 已结束循环的截止边界同步修复

日期：2026-10-21。状态：本地代码已修复，未打包、发布或修改真实账号数据。

## 复现与原因

用户反馈批量缩短循环截止时间后，原先 14 期在同步后变为 15 期。
使用合成数据复现了相同现象：保留 14 条已结束期次和第 15 期的本地删除标记，模拟云端返回能赢过该删除标记的旧第 15 期，旧边界校验最终保留了 15 条活动记录。

原 `_pruneRecurrenceOccurrencesAfterEndDates` 只检查 `recurrence != none` 的活动规则。正常滚动在循环结束后会清除这个字段，虽然 `recurrenceEndDate` 仍保留，后续同步却不再检查它。截止日期之外的实例因而可能重新进入系列。

这证明了代码中的失效路径；没有读取用户实际数据库或线上日志，不能据此断言真实账号一定经过了同一条路径。

## 修改

- 没有活动规则时，从未删除、仍保留截止日期的系列记录中按既有 LWW 顺序选取截止边界。活动规则继续优先，包括用户主动延长为无限循环的规则。
- 普通读取和同步合并后均检查边界，超出截止日期的期次软删除并排队回传。
- 边界修复同时保留实例与规则的本地及服务端版本基线，避免用户同时延长循环时用过期规则提交维护。
- 保留期次的完成、跳过状态不变；不新增字段、依赖或服务端改动。截止日期本身若已被覆盖，本轮不会猜测并重建原值。

## 验证

临时关闭新增的已结束规则回退后，两个新增用例失败，真实 SQLite + 回环 HTTP 用例明确得到 `Expected 14 / Actual 15`；恢复修复后通过。日志：`/tmp/cdt_recurrence_boundary_reproduced.log`。

以下 8 个文件共 **82 项通过**，包含连续两轮同步、普通读取修复、无限循环延长、完成和跳过保留、删除恢复及旧数据保护：

```bash
flutter test --no-pub \
  test/models/todo_recurrence_series_test.dart \
  test/services/todo_recurrence_sync_regression_test.dart \
  test/services/todo_recurrence_delete_storage_test.dart \
  test/services/todo_recurrence_restore_storage_test.dart \
  test/services/todo_recurrence_delete_service_test.dart \
  test/services/todo_recurrence_restore_service_test.dart \
  test/services/todo_lww_service_test.dart \
  test/services/sync_oplog_policy_test.dart --reporter expanded
```

日志：`/tmp/cdt_recurrence_boundary_final_tests.log`。本轮涉及的 5 个 Dart 文件执行 `dart analyze` 无问题，定向 `git diff --check` 通过。

扩大验证时另有两项限制：

- `todo_trash_purge_storage_test.dart` 中“部分删除系列只清理墓碑，活动期次与规则保留”要求原锚点保留 daily，但读取时跨日滚动已经将规则转给后续期次；移除本轮新增的读取校验后仍相同失败。
- `todo_edit_exit_protection_test.dart` 被现有 `finance_widgets.dart:2005` 的 `String?` 放入 `List<String>` 编译错误阻塞。

未运行全项目测试、全项目 analyze、构建、部署或真实多设备验收。工作区中的其他并行改动保留，未纳入本轮修复范围。
