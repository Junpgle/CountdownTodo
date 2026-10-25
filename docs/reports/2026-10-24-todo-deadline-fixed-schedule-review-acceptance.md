# 第40轮验收：待办期限调整后的关联固定日程复核

日期：2026-10-24（北京时间）

状态：**技术验收通过，等待用户确认**

方案：[`docs/proposals/2026-10-24-todo-deadline-fixed-schedule-review.md`](../proposals/2026-10-24-todo-deadline-fixed-schedule-review.md)

## 实现结果

- 在共用待办编辑器保存路径检查已修改期限的关联日程。定时待办按新截止时刻与日程开始时刻比较；日期待办按本地自然日比较，同日不制造误报。
- 仅对保存前团队归属一致、尚未开始且有效的日程展示复核。完成、跳过、删除、取消、进行中、已结束和时间待定对象不会产生风险项。
- 复核弹窗展示待办期限前后值、日程开始时间和明确的非冲突说明；重复日程按系列汇总，并支持展开更多结果。取消会留在编辑页并保留输入。
- 关联日程在弹窗前后重新读取；待办事务内校验关联日程集合及完整快照，发现并发变化时拒绝使用旧复核结果保存。
- 复核读取失败会保留输入并报告保存失败，不会把错误当作没有关联日程。没有新增数据库字段、迁移、服务端接口或同步协议。
- 入口覆盖首页、搜索、待安排清单、规划清理和冲突收件箱使用的共用编辑器保存回调。

## 自动化验收

以下定向命令全部通过，共 **29 项测试**：

```text
flutter test --no-pub \
  test/services/todo_deadline_fixed_schedule_review_service_test.dart \
  test/services/todo_deadline_fixed_schedule_review_storage_test.dart \
  test/widgets/todo_deadline_fixed_schedule_review_dialog_test.dart \
  test/widgets/todo_deadline_fixed_schedule_review_flow_test.dart \
  test/widgets/todo_edit_exit_protection_test.dart \
  --reporter compact
```

测试构成：期限规则 6 项、存储和并发快照 3 项、复核弹窗 3 项、实际编辑流程 2 项、待办退出保护回归 15 项。

其它检查：

- 对本轮相关 20 个 Dart 源码和测试路径运行 `dart analyze`：`No issues found!`。
- `git diff --check`：通过；本轮新增源码、测试和文档未发现行尾空格。
- `flutter build web --release --no-pub`：成功，生成 `build/web`。Flutter 的 Wasm dry-run 也通过。
- 本轮新建 Dart 源码与测试已运行 `dart format`；为避免重排待办编辑器中既有的无关代码，未重新格式化整个大型编辑器文件。

## 界面证据

截图来自 Flutter WidgetTester：视口 360×800、深色主题、字号 1.25 倍，已加载本机中文与 Material 图标字体。

![第40轮期限复核弹窗：窄屏、深色、大字号](/Users/junpgle/StudioProjects/CountdownTodo/test/widgets/goldens/round_40_deadline_review_phone_dark_large.png)

截图覆盖期限调整前后、日程开始时间、“不代表时间冲突”说明以及“返回修改／确认保存”操作。它是 WidgetTester 输出，不是运行中的真机或浏览器截图。

## 尚未覆盖与提交状态

- 未在真实 Android／iOS 设备或运行中的 Web 浏览器完成手工流程验收；当前证据为定向 WidgetTester、SQLite 测试和 Web release 编译。
- 未运行全仓库 `flutter test`；验收采用上述与共用编辑器相关的定向回归集。
- 按用户约定，等待用户确认后才提交本轮文件。Android 到课提醒、财务页面和版本号等工作区既有改动均未纳入本轮，也没有推送或部署。
- 用户曾要求方案阶段使用 GPT‑6.1 sol／中、实施阶段使用 GPT‑6 luna／Max；当前会话环境没有切换或验证模型／思考强度的入口，因此本报告不声称使用了指定模型。
