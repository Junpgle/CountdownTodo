# 第三轮补充：新建规划只选择未完成待办

日期：2026-10-09。

## 改动

- 共享规划编辑器先过滤已完成待办，再折叠循环实例；已删除待办继续由现有折叠工具排除。
- 没有可选未完成待办时显示空状态，禁用保存与保存并专注。
- 待办列表刷新后，如原选择完成或失效，清空选择并要求明确重选，不自动换成其他待办。
- 历史规划保留原待办关联和显示；其已完成关联项不可重新选择，其他已完成项不进入菜单。
- 新建或更换关联时，保存前检查当前草稿待办状态；手动保存的真实数据库事务再次检查最新完成／删除状态。拒绝时保留草稿，规划及oplog零写入。
- 推荐保存与漏做重排继续使用既有严格校验。

## 验收

```sh
flutter test --no-pub test/widgets/plan_block_editor_sheet_test.dart test/widgets/missed_plan_recovery_flow_test.dart test/utils/todo_recurrence_picker_test.dart test/services/plan_availability_repository_test.dart --timeout 45s
flutter analyze --no-pub lib/widgets/plan_block_editor_sheet.dart test/widgets/plan_block_editor_sheet_test.dart
/Users/junpgle/develop/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib/widgets/plan_block_editor_sheet.dart test/widgets/plan_block_editor_sheet_test.dart
git -c core.fsmonitor=false diff --check
```

72项测试通过，其中新增7项界面测试，涵盖完成／删除过滤、循环代表实例、空列表、历史关联、草稿完成拦截、列表刷新明确重选，以及真实SQLite中完成／删除后的手动保存拒绝和零写入。

2文件静态分析无问题；2文件格式检查零变化；diff检查通过。
日志：`/tmp/plan-unfinished-picker-verified-tests.log`、`/tmp/plan-unfinished-picker-verified-analyze.log`。

未运行全仓测试、浏览器或原生实机验收。未提交、推送或部署。其他在途改动保留。
