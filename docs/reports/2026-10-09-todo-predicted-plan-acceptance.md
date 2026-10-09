# 第三轮补充：首页待办编辑进入预测规划

日期：2026-10-09。

## 交付行为

首页编辑待办 → 计划安排 → 新建规划块，直接打开共享规划编辑器，关联当前具体未完成待办。今日计划入口保留；按钮区域可自动换行。已完成、已删除或编辑草稿标记完成时禁用新建入口。

弹窗先调用现有完成时间预测，显示预测进度；预测完成后用预测时长初始化推荐面板，显示“预计用时”，恢复当前账号避让偏好，然后自动查找并填入第一条有效建议。没有先运行固定30分钟查询。默认展示五个候选，允许切换时段或调整时长。

预测和自动查找阶段禁止直接保存默认区间；手动调整可取消自动采用。预测失败显示手动设置提示，不静默发起固定时长查找。无可用时段或日历读取失败显示既有反馈；应用内降级仍需明确点击。预测和查询晚返回不覆盖已经修改的草稿，也不更新已关闭弹窗。

只填草稿，最终保存／启动专注仍需用户点击，并复用现有推荐时段复查。关闭零规划／待办／oplog写入。全天日视图点击／拖选和漏做重排不启用本入口的自动预测初始化。

## 验收

```sh
flutter test --no-pub test/widgets/todo_edit_plan_entry_test.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/missed_plan_recovery_flow_test.dart --timeout 45s
flutter analyze --no-pub lib/widgets/plan_availability_panel.dart lib/widgets/plan_block_editor_sheet.dart lib/widgets/todo_section_widget.dart lib/widgets/todo_edit_screen.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/todo_edit_plan_entry_test.dart
/Users/junpgle/develop/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib/widgets/plan_block_editor_sheet.dart lib/widgets/plan_availability_panel.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/todo_edit_plan_entry_test.dart
git -c core.fsmonitor=false diff --check
```

69项相关界面测试全部通过。新增10项覆盖实际待办编辑页入口与完成状态、真实预测结果传递、预测75分钟时查询前无读取且首次只查75分钟、默认第一建议、恢复避让、切换其他候选、取消零写入、预测／查询期间修改与关闭、无空闲和日历失败／明确降级。

6文件静态分析无问题；4个独立维护文件格式检查零变化；两个大型旧文件仅改相关方法与导入，避免全文件格式变动；diff检查通过。
日志：`/tmp/todo-predicted-plan-verified-tests.log`、`/tmp/todo-predicted-plan-verified-analyze.log`。

实际入口验证使用TodoEditScreen及隔离SQLite；未在完整首页或原生实机点击验收，也未做浏览器视觉验收。未运行全仓测试、发布构建，未提交、推送或部署。其他在途改动保留。
