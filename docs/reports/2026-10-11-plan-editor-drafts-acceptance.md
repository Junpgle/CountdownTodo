# 第九轮：规划草稿暂存与退出保护验收

日期：2026-10-11（北京时间）。用户回复“批准第九轮”批准[完整方案](../proposals/2026-10-11-plan-editor-drafts.md)，随后于2026-10-11回复“通过，准备第十轮方案”。第九轮验收通过。

## 交付结果

- 普通新建规划支持主动保留本机草稿，退出时提供继续编辑、放弃修改、保留草稿并离开。仅自动估时／推荐、不修改、全部改回原值时不打扰。
- 时间轴、首页待办编辑、待规划入口复用原整页编辑器；相同待办提示主动恢复，切换待办立即清掉旧提示，异步结果不能串入新任务。规划页更多菜单进入独立草稿列表。
- 每个账号及当前成员最多5份；更新／删除校验修订号，满额不清旧稿。失败留在原页，草稿读取失败不冒充空列表；恢复失败不出现可保存的空表单，允许重试。
- 完整恢复备注、时段、提醒、单轮番茄和轮数；保留具体待办UUID，不按同名替换。过期日期可修改，时区变化需确认；推荐与旧追加确认作废，保存前重新核对占用和当前安排。
- 草稿预留固定目标规划UUID。真实保存事务复核草稿修订，成功清理对应草稿；清理失败单独提示，恢复时识别已有规划，阻止重复新建。
- 已有规划、冲突调整和漏做重排仅增加退出保护。底部编辑器禁用直接下滑关闭，按钮、遮罩和系统返回走保护；时间轴拖动新建／移动保持。

功能入口、规则及限制见[功能说明](../features/plan-editor-drafts.md)。本轮没有新增后端、依赖、权限或发布配置。

## 自动验收

最终 **37个相关测试文件、538项全部通过**，`01:07 +538: All tests passed!`。日志：`/tmp/plan_draft_final_full_regression.log`。此前不同批次通过数不累加。

| 内容 | 已验证范围 |
| --- | --- |
| 数据库 | schema58新建、57升级、重新打开后完整字段保留；原待办不受影响 |
| 容量与并发 | 6次并发暂存最多5份；同修订更新只允许一个成功；旧修订更新、删除、恢复及正式保存被拒绝 |
| 身份与目标 | 账号／成员隔离；具体UUID；完成、删除、冲突、缺失待办拒绝；不猜同名任务 |
| 内容完整性 | 完整配置往返、稳定有界摘要排序；坏JSON、未知格式保留可删除；256KiB超限失败不截断 |
| 数据边界 | 暂存不写待办、正式规划、oplog或业务审计；实际业务导出文件与实际云同步HTTP请求体不包含草稿 |
| 退出流程 | 无修改返回、改回原值、继续／放弃／保留；暂存失败不离页；系统返回先关闭内部查找弹窗；特殊编辑遮罩退出保护 |
| 恢复与保存 | 过期、忙碌、时区确认、日历失败显式应用内降级；待规划最新安排重新确认；真实保存一个目标UUID及oplog；清理失败后不重复创建 |
| 异步与失败 | 切换待办清除旧提示；失败恢复阻止空提交并可重试；保存失败保留内容；恢复修订过期拒绝 |
| 界面与既有回归 | 小屏大字体深色无溢出；估时、空闲、跨天日历、规划拖动撤销、冲突改期、漏做恢复、待规划、复盘等相关回归 |

测试使用隔离SQLite及合成数据。云请求测试发往本机临时HTTP服务，检查实际ApiService请求体，不是线上同步验收；业务导出检查实际临时文件。局域网同步仅核对既有明确字段名单，未进行两台设备握手。

准确文件清单和命令如下（同时保存在`/tmp/plan_draft_regression_files.txt`）：

```sh
flutter test --no-pub \
  test/services/time_estimation_service_test.dart \
  test/services/time_estimation_repository_test.dart \
  test/widgets/time_estimation_hint_test.dart \
  test/widgets/time_estimation_flow_test.dart \
  test/services/plan_drag_service_test.dart \
  test/widgets/plan_drag_undo_test.dart \
  test/services/plan_conflict_review_service_test.dart \
  test/widgets/plan_conflict_review_test.dart \
  test/services/missed_plan_recovery_service_test.dart \
  test/widgets/missed_plan_recovery_flow_test.dart \
  test/services/plan_availability_service_test.dart \
  test/services/plan_availability_repository_test.dart \
  test/services/plan_availability_preferences_test.dart \
  test/services/plan_execution_repository_test.dart \
  test/services/device_calendar_read_service_test.dart \
  test/services/device_calendar_refresh_test.dart \
  test/widgets/plan_availability_panel_test.dart \
  test/widgets/plan_block_editor_sheet_test.dart \
  test/widgets/todo_edit_plan_entry_test.dart \
  test/widgets/plan_execution_view_test.dart \
  test/widgets/device_calendar_event_detail_screen_test.dart \
  test/widgets/course_month_view_device_calendar_test.dart \
  test/widgets/device_calendar_home_schedule_test.dart \
  test/services/schedule_conflict_service_test.dart \
  test/services/calendar_sync_service_test.dart \
  test/models/todo_time_semantics_test.dart \
  test/widgets/app_dialogs_test.dart \
  test/widgets/add_todo_screen_test.dart \
  test/services/plan_backlog_repository_test.dart \
  test/services/plan_todo_guard_test.dart \
  test/widgets/plan_backlog_screen_test.dart \
  test/services/plan_review_repository_test.dart \
  test/widgets/plan_review_screen_test.dart \
  test/services/plan_editor_draft_repository_test.dart \
  test/services/plan_editor_draft_integrity_test.dart \
  test/widgets/plan_editor_drafts_test.dart \
  test/services/database_schema_history_test.dart --reporter expanded
```

变更相关12个源码／测试入口Dart静态分析无问题，日志`/tmp/plan_draft_final_analyze.log`。`todo_edit_screen.dart`是part文件，通过所属`todo_section_widget.dart`分析。未运行全仓分析或全仓格式化；仅格式化新增文件。暂存和未暂存差异均执行`git diff --check`。

初测保留日志包含两处后续修正：恢复失败后的重试按钮曾被禁用层遮挡，已修正并加入重试成功断言；新增对话框测试初次因忙碌动画下使用pumpAndSettle超时，改为有界推进后点击确认，最终28项Widget专项及完整回归通过。

## 存储与恢复边界

本地schema58增加`local_plan_editor_drafts`及成员排序索引。仓储只写该表，业务查询和占用计算不读取草稿；无草稿通知、远程AI或同步触发。业务导出、云与局域网同步按明确对象名单读取。完整数据库文件副本可能包含草稿。

本轮采用**主动暂存**：系统强杀、刷新或关窗口前未主动保留的最新修改不保证恢复，也不拦截浏览器关标签。普通退出登录保留原账号草稿；切换身份不能继续旧页面操作。账号数据库整个移除时草稿随文件移除。

## 浏览器验收

浏览器采用独立合成账号、正式编辑器／仓储／保存路径、Web SQLite。手机日历停用，网络地址指向本机无服务端口，不读取个人数据，不请求远程AI。

在8964验证备注、30分钟单轮番茄、15分钟提醒恢复、真实保存后草稿列表归零，以及刷新后主动保留的草稿仍存在。早期合成任务使用非UUID导致恢复失败，改为有效UUID并更换隔离合成账号；产品没有增加按标题或伪ID匹配。

早期占用观察使用固定上午编辑器时钟、当天14–15时段，原规划时间轴使用真实下午时钟并把过期规划标记漏做；这种记录按既有规则不再占用，不作为冲突拒绝证据。最终改用次日有效占用，并在新端口8965载入最终构建，避免旧资源缓存。未修改产品的占用规则或漏做业务。

最终预览：[本机第九轮预览](http://127.0.0.1:8965/)。最终构建先在540×680验证：恢复14–15时段被次日有效规划占用时明确拒绝，原表单保留；选择重新读取的08–09推荐后真实保存成功，草稿列表变为0/5。又在390×844刷新验证草稿仍存在、恢复及占用拒绝，并复核修改后的退出保护。随后在320×844、1.8倍字体、深色和玻璃开启条件下验证退出对话框完整换行且能保留草稿；1280×900恢复编辑页完整展示。

- [最终540宽退出确认](/tmp/plan-draft-evidence/final-exit-confirm.png)
- [最终540宽恢复后占用拒绝](/tmp/plan-draft-evidence/final-conflict-rejected.png)
- [最终390手机草稿列表](/tmp/plan-draft-evidence/final-mobile-list.png)
- [最终390手机占用拒绝](/tmp/plan-draft-evidence/final-mobile-conflict.png)
- [最终390手机退出保护](/tmp/plan-draft-evidence/final-mobile-exit.png)
- [最终桌面恢复与重新选择推荐](/tmp/plan-draft-evidence/final-desktop-restored.png)
- [最终保存后草稿为空](/tmp/plan-draft-evidence/final-saved-empty.png)
- [最终320大字体深色退出确认](/tmp/plan-draft-evidence/final-large-font-exit.png)
- [前一构建手机恢复完整配置](/tmp/plan-draft-evidence/mobile-restored.png)
- [前一构建刷新后草稿仍存在](/tmp/plan-draft-evidence/mobile-reloaded-list.png)

前一构建截图和最终截图分开标记，不冒充同一阶段证据。`mobile-new-conflict.png`是早期时钟不一致场景的中间画面，不用作冲突拒绝证明。

最终生产代码构建通过，日志`/tmp/plan_draft_final_web_build.log`，53.5秒；随后仅调整忽略的合成预览种子，构建43.0秒通过，日志`/tmp/plan_draft_fixture_final_web_build.log`：

```sh
flutter build web --no-pub --target .dart_tool/plan_draft_preview.dart \
  --output /tmp/countdown-plan-draft-preview --pwa-strategy=none \
  --no-web-resources-cdn
```

预览入口在忽略的`.dart_tool/`，构建和截图在`/tmp/`，未加入发布应用。Wasm预检及构建成功不代表原生设备验证。

## 尚未验证与交付状态

未运行全仓测试／分析；未做Android／iOS／macOS／Windows实机系统返回、原生弹层手势、进程终止后重开及真实用户数据库升级；未做线上云同步、双设备局域网同步或实体手机日历权限测试。这些不计入本次已通过范围。

本轮未由当前执行过程进行提交、推送、部署、打包发布。共享工作区在执行期间出现其他操作者的提交，包含本轮源文件与测试；本报告不把这些提交归为当前执行过程，也未撤销它们。

用户已验收通过第九轮；下一步准备第十轮完整方案，获批准后再实施。
