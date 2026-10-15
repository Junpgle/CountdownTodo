# 第十轮：可用时段前后缓冲验收

日期：2026-10-11（北京时间）。用户明确回复“批准第十轮，按方案实施并验收”，随后回复“通过，请继续”。[方案](../proposals/2026-10-11-plan-availability-buffers.md)已实施并通过用户验收。以下测试结果为该轮执行时的证据，后续工作区变更不在此历史结果的证明范围内。

## 交付

- 独立的开始前／结束后缓冲：默认0，快捷选择及0–120整数自定义，账号本机记忆，v1避让设置兼容升级。
- 普通新建页保持推荐结果；设置放在自定义弹窗。小屏大字体纵向排列，空间充足时并排。
- 推荐、最新来源复核和SQLite写事务使用相同缓冲规则，邻日来源保留真实边界；原本跨天／全天手机事件仍不占空闲，午休等避让不额外扩张。
- 无结果支持显式“本次不留缓冲再查找”，不覆盖默认、不自动采用；设置变更、失败、损坏和异步旧响应均有处理。
- 草稿恢复、冲突改期、漏做重新安排、显式应用内日历降级传递同样参数。缓冲不写进任务时长、番茄预算或复盘。

入口、计算及限制见[功能说明](../features/plan-availability-buffers.md)。没有新增数据库迁移、依赖、后端、权限或同步字段。

## 自动验收

最终 **39个测试文件、579项全部通过**：`01:08 +579: All tests passed!`。日志：[完整回归](/tmp/plan_buffer_acceptance_regression.log)。此前的578项及专项通过数不累加。

| 范围 | 已验证内容 |
| --- | --- |
| 区间 | 前后不对称、仅一侧、0值贴边、恰好满足、重叠合并、午夜邻日、UTC和自然日边界；任务时长不变；避让不扩张 |
| 来源与保存 | 真实SQLite课程／固定安排／规划／兼容旧执行区间；同日手机事件、原跨天忽略；仅排除编辑UUID；新增非重叠邻项侵入缓冲拒绝；读后事务竞态拒绝且无业务写入 |
| 记忆 | v1保留有效避让，v2账号隔离，快速写入快照、旧避让写入不清缓冲；默认值变化拒绝旧候选；损坏配置重置不清有效避让 |
| 界面 | 自定义整数校验／取消、关闭弹窗保留选择、设置改变刷新、当前查询无缓冲／恢复默认、写失败诚实提示、前台恢复、迟到结果丢弃、下拉控件状态及焦点保留 |
| 恢复与既有功能 | 草稿邻项侵入拒绝、应用内降级保留缓冲及时长；手动改期和漏做重排同样拒绝；估时、日历、拖动撤销、待规划、复盘、草稿等既有相关回归 |

额外在 `TZ=America/New_York` 运行服务测试，**26项通过**，覆盖2026-03-08、2026-11-01自然日与实际时间差；日志：[时区测试](/tmp/plan_buffer_dst_final.log)。这是服务层时区环境验证，不是修改真机系统时区。

12个相关源码／测试路径的直接Dart静态分析 **No issues found**：[日志](/tmp/plan_buffer_acceptance_analyze.log)。Web隔离预览构建成功：[最终构建](/tmp/plan_buffer_web_focus_fix.log)。`git diff --check`及暂存区同项检查通过。未运行全仓库分析、全部测试或原生打包。

准确回归文件清单：

```text
test/services/time_estimation_service_test.dart
test/services/time_estimation_repository_test.dart
test/widgets/time_estimation_hint_test.dart
test/widgets/time_estimation_flow_test.dart
test/services/plan_drag_service_test.dart
test/widgets/plan_drag_undo_test.dart
test/services/plan_conflict_review_service_test.dart
test/widgets/plan_conflict_review_test.dart
test/services/missed_plan_recovery_service_test.dart
test/widgets/missed_plan_recovery_flow_test.dart
test/services/plan_availability_service_test.dart
test/services/plan_availability_repository_test.dart
test/services/plan_availability_preferences_test.dart
test/services/plan_execution_repository_test.dart
test/services/device_calendar_read_service_test.dart
test/services/device_calendar_refresh_test.dart
test/widgets/plan_availability_panel_test.dart
test/widgets/plan_block_editor_sheet_test.dart
test/widgets/todo_edit_plan_entry_test.dart
test/widgets/plan_execution_view_test.dart
test/widgets/device_calendar_event_detail_screen_test.dart
test/widgets/course_month_view_device_calendar_test.dart
test/widgets/device_calendar_home_schedule_test.dart
test/services/schedule_conflict_service_test.dart
test/services/calendar_sync_service_test.dart
test/models/todo_time_semantics_test.dart
test/widgets/app_dialogs_test.dart
test/widgets/add_todo_screen_test.dart
test/services/plan_backlog_repository_test.dart
test/services/plan_todo_guard_test.dart
test/widgets/plan_backlog_screen_test.dart
test/services/plan_review_repository_test.dart
test/widgets/plan_review_screen_test.dart
test/services/plan_editor_draft_repository_test.dart
test/services/plan_editor_draft_integrity_test.dart
test/widgets/plan_editor_drafts_test.dart
test/services/database_schema_history_test.dart
test/services/plan_availability_buffers_test.dart
test/widgets/plan_availability_buffers_test.dart
```

命令：

```sh
/Users/junpgle/develop/flutter/bin/flutter test --no-pub $(cat /tmp/plan_buffer_regression_files.txt) --reporter expanded
TZ=America/New_York /Users/junpgle/develop/flutter/bin/flutter test --no-pub test/services/plan_availability_buffers_test.dart --reporter expanded
/Users/junpgle/develop/flutter/bin/flutter build web --no-pub --target .dart_tool/plan_buffer_preview.dart --output /tmp/countdown-plan-buffer-preview --pwa-strategy=none --no-web-resources-cdn
```

## 浏览器验收

本机隔离地址 [验收预览](http://127.0.0.1:8966/)，账号与数据库均为合成数据，没有操作用户正式数据。使用正式编辑器、可用时段查询与保存路径；忽略的预览入口只负责初始化合成课程08–10、会议11–12、任务截止10月12日11:00，以及模拟邻项／核对数据库记录。截图顶部工具条属于验收工具，产品没有新增这组按钮。

| 操作 | 实际观察 |
| --- | --- |
| 首次默认 | 0/0下推荐10:00–10:30、10:30–11:00 |
| 前10后5 | 推荐10:10–10:40，真实任务仍为30分钟 |
| 60分钟无结果 | 显示截止前不足60分钟及当前缓冲；没有自动放宽 |
| 显式本次无缓冲 | 出现10:00–11:00、60分钟；显示“本次未留缓冲”；恢复默认仍为10/5 |
| 新增邻项 | 在已选10:10–10:40后，模拟10:00–10:05；虽然不重叠，保存拒绝且内容保留 |
| 有效保存 | 取消模拟邻项，刷新并重选，保存后核对为正式规划1份、本机草稿0份、最近30分钟 |
| 浏览器刷新 | 默认摘要仍为前10后5，已存规划继续占用 |
| 草稿恢复 | 保留备注及10:00–10:30原时段；恢复后显示当前10/5，保存再次因已占用拒绝，草稿仍可编辑 |
| 布局 | 390×844手机、1280×900桌面并排；320×844、1.8倍字体、深色玻璃模式纵排，弹窗可滚动操作 |

截图：报告曾列出的 `/tmp/plan-buffer-evidence/` 目录当前不存在，因此这些图片无法随本次提交交付。上表保留当次浏览器操作记录；控件布局和焦点行为由 Widget 回归覆盖。

## 诊断记录与验证边界

浏览器预览启动／窗口聚焦阶段捕获到Flutter `WidgetsBindingObserver.didChangeViewFocus` 的 `RenderBox was not laid out` 诊断。带详细断言的独立诊断预览在启动时记录了同类异常；进入界面后的查找、选择、修改缓冲与保存没有新增同类记录，未观察到相应操作失效。不能据此宣称控制台全程零异常，也未将其认定为已经修复的产品问题。下拉控件改用稳定Key保留状态，新增焦点回归通过。

Android/iOS手机日历由桥接合成数据测试覆盖；真实权限、系统日历、系统返回、原生通知和键盘未实机验收。多窗口默认值变化由偏好重载／保存守卫测试覆盖，多设备同时写入或真实云同步不在本轮验收范围。外部系统日历与本地数据库不能构成同一原子事务。

本执行过程没有主动提交、推送、发布或部署。共享工作区期间存在外部提交和其他模块编辑，保留原状；测试日志描述当次执行证据，不代表其他并行模块的验收。
