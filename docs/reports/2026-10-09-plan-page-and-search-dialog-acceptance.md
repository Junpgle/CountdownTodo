# 第三轮补充：整页新建规划与自定义查找弹窗

日期：2026-10-09。

## 交付行为

- 首页编辑待办、日视图点击／拖选、漏做重排进入独立页面，使用标准页面过渡和返回按钮。
- 新建页推荐区域自动查找并展示最多两个可用时段，不内嵌日期、时长、范围、避让和数量表单。无可用时间或读取失败时显示对应提示。
- “自定义寻找时段”打开有限高度的可滚动弹窗，支持日期、今天／明天快捷选择、15／30／45／60分钟及自定义时长、查找范围、3／5／8个候选、午休／午餐／晚餐及自定义避让。默认五个候选；实际不足时按可用数量展示。
- 在弹窗选择时段后关闭并填回新建页；即便选择的是第三个或之后的候选，也会保留在主页面的两条结果中。取消弹窗保留原草稿，重新打开恢复当前查询条件和账号避让偏好。
- 首页待办入口先完成现有完成时间预测，再按预测时长查找并采用第一建议。预测失败不自动查占位30分钟；可进入自定义查找手动调整。拖选入口保留拖选时间，推荐结果只供选择。
- 外部安排变化使已采用推荐失效，刷新候选但不自动覆盖草稿。重新选择后才恢复推荐保存；保存继续执行既有新鲜度、待办状态、占用与账户检查。
- 原有规划编辑保留共享编辑浮层和展开动画。其他设置保持并排；规划时间轴仍保留24小时拖动操作。

## 验收结果

最终版本139项规划相关服务／界面测试全部通过，新增8项覆盖独立路由、预测完成前零查询、两条默认结果、表单迁入弹窗、8个方案选第五项回填、取消零保存、查询／避让恢复、外部刷新失效保护、日历错误及明确应用内降级，以及窄屏／横屏／大字体／键盘布局。实际首页编辑、时间轴点击／拖动、今日与统计漏做入口的断言同步验证页面路由；隔离SQLite继续验证取消零写入和保存边界。

9文件定向分析无问题，5个独立维护文件格式检查零变化，diff检查通过。大型旧入口文件仅修改相关调用，保留其他在途改动。

浏览器使用正式编辑器组件与合成数据完成手机390×844及桌面默认尺寸验收：默认75分钟预测、两个推荐、自定义弹窗、午休避让、更多候选以及第三个候选返回后保留在两个结果中。预览只写内存，不读取个人数据；本轮预览标签页及临时本地服务器已关闭，浏览器尺寸已恢复。

截图：

- [手机新建页](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-page-mobile.png)
- [自定义弹窗结果](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-custom-search-mobile.png)
- [自定义第三项填回](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-page-custom-selected-mobile.png)

```sh
flutter test --no-pub test/widgets/plan_block_editor_sheet_test.dart test/widgets/todo_edit_plan_entry_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/missed_plan_recovery_flow_test.dart test/services/plan_availability_service_test.dart test/services/plan_availability_repository_test.dart test/services/plan_availability_preferences_test.dart test/services/missed_plan_recovery_service_test.dart --reporter compact
flutter analyze --no-pub lib/widgets/plan_availability_panel.dart lib/widgets/plan_block_editor_sheet.dart lib/widgets/missed_plan_recovery_flow.dart lib/widgets/todo_section_widget.dart lib/screens/todo_plan_screen.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/todo_edit_plan_entry_test.dart test/widgets/missed_plan_recovery_flow_test.dart
/Users/junpgle/develop/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib/widgets/plan_availability_panel.dart lib/widgets/plan_block_editor_sheet.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/todo_edit_plan_entry_test.dart test/widgets/missed_plan_recovery_flow_test.dart
git -c core.fsmonitor=false diff --check
```

最终日志：`/tmp/plan_page_final_tests.log`、`/tmp/plan_page_final_analyze.log`。合成预览构建日志：`/tmp/plan_page_preview_build.log`。

未运行全仓测试，未做Android／iOS实机验收；浏览器手机尺寸不等同手机实机。仅生成本地合成预览构建，未做发布构建、提交、推送或部署。第四轮仍暂缓。
