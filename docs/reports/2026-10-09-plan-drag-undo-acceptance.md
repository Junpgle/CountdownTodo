# 第五轮：规划拖动撤销与可靠保存验收

日期：2026-10-09（北京时间）。用户已确认“同意第五轮，按方案实施并验收”，交付后回复“通过”。状态：实现完成，相关本地验收及用户验收均通过；第六轮另提方案。

## 交付结果

- 保留全天24小时一屏、空白拖选新建、长按移动和边缘缩放。拖动预览单独存放，不修改传入的规划记录；跨小时分段保留原手势锚点，共用一次提交。
- 整块移动保持完整时长，60分钟规划到午夜最多移动为23:00–24:00。左右缩放累计从按下开始的位移，慢拖也能吸附；最小时长沿用5／10／15／30分钟粒度。本地次日边界使用日期构造，兼容夏令时23／25小时日。
- 无位移、移回原位置或取消不写数据库。有效松手只保存一次，保存期间显示状态并阻止重复操作；失败结束预览、刷新真实记录并提示原因。
- 成功后约6秒显示前后时段及撤销按钮，桌面提示限制宽度，右侧留出工具图标。提示消失后仍可通过“撤销上次调整”恢复最近一次成功移动／缩放；后续失败、取消和无变化不替换已有机会。
- 撤销恢复原时间与计划分钟数，保持同一UUID、备注、提醒、番茄设置、实际专注、记录关联、设备与日历身份。它是一笔新版本和新oplog，调整与撤销各自原子提交；其他记录逐字段保持不变。
- 保存及撤销事务复核账号、原版本、更新时间、完整内容、有效待办、状态与专注运行标记。并发修改、待办完成／删除／冲突、账户切换或恢复时段已结束时拒绝旧操作；暂时读取／保存失败保留重试机会，oplog故障完整回滚。
- 仅未结束的planned／reminded／delayed真实规划可调整。专注中、历史状态、映射来源及实际记录保持只读。切日、切账号和离页清除撤销；后台取消未提交预览，前台恢复重新读取和核验，没有后台轮询。
- 直接拖动和撤销保留软冲突规则，不新增占用确认弹窗或自动改期。第四轮入口随保存数据刷新；午休／用餐偏好继续约束主动查找与编辑器保存。

## 自动验证

23个相关测试文件共 **313项通过**，覆盖第五轮新增服务33项、正式界面25项，以及原有空闲推荐、避让记忆、第三轮恢复、第四轮改期、实际记录和日历等流程。最后补充生产数据库路径的账户失效判断后，第五轮 **58项再次通过**；紧凑提示调整后，正式界面 **25项再次通过**。

正式手势测试先复现并失败：22:30–23:30移动到午夜时被截为45分钟；长按不移动仍递增版本。修复后两项及其他正式手势回归通过。初始失败日志 `/tmp/plan_drag_baseline.log`。

| 验收项 | 实际证据 |
| --- | --- |
| 时长与吸附 | 4种粒度、两端边界、左右慢拖20次小位移、最小长度、跨小时、月底、取消、移回原位；手指释放前数据库和汇总不变 |
| 保存与撤销 | 同一UUID、配置和实际身份保留；各一条oplog；最近一次、6秒提示消失后图标、失败保留前一次、连击只写一次 |
| 状态与失效 | 历史状态、专注运行标记、原记录内容／版本变化、删除、无效待办、原时段过期、切日／离页／账户／前后台和延迟保存返回 |
| 事务与恢复 | oplog触发故障完整回滚后可重试；读取失败不误判删除；保存失败刷新真实位置，撤销失败保留入口 |
| 占用规则 | 直接放入重叠或避让区间可保存；恢复原时间后新增会议仍由第四轮提示，不进行自动改期 |
| 布局 | 320×640、390×844、720×360、1280×900，1.6／2.0字号，深浅色与普通／玻璃；无溢出，撤销可达，时间轴没有滚动容器 |

完整相关回归命令：

```sh
flutter test --no-pub \
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
  test/widgets/app_dialogs_test.dart --reporter expanded
```

日志：`/tmp/plan_drag_full_tests.log`。末次聚焦重跑：`/tmp/plan_drag_final_new_tests.log`（58项）、`/tmp/plan_drag_final_layout_tests.log`（25项）。使用隔离SQLite、合成样本、模拟平台桥及可控时钟。

显式纽约时区执行夏令时边界测试通过（1项），覆盖2026-03-08的23小时日及2026-11-01的25小时日，60分钟移动到末端仍为23:00–次日00:00：

```sh
TZ=America/New_York flutter test --no-pub \
  test/services/plan_drag_service_test.dart \
  --plain-name '夏令时日期使用本地午夜边界，23或25小时日仍保时长' \
  --reporter expanded
```

日志：`/tmp/plan_drag_dst_test.log`。4个源码／测试文件静态分析无问题：

```sh
flutter analyze --no-pub \
  lib/services/plan_drag_service.dart \
  lib/screens/todo_plan_screen.dart \
  test/services/plan_drag_service_test.dart \
  test/widgets/plan_drag_undo_test.dart
```

日志：`/tmp/plan_drag_final_analyze.log`。新增3个Dart文件格式检查零变化，旧大型日视图只修改相关区域；`git diff --check`通过。

## 浏览器实际操作

使用正式`TodoPlanScreen`、正式保存服务与Web SQLite，单独localhost端口和合成账户，仅关闭同步；未读取或修改个人业务数据。样本“复习高数”19:15–20:15、60分钟、已有5分钟实际投入，小组讨论20:20–21:00。

手机390×844与桌面1280×720实际拖动结束边缘至20:30，保存后计划75分钟、原实际5分钟、第四轮出现1条重叠；通过工具区撤销恢复19:15–20:15及60分钟，重叠提示消失。浏览器验收的是边缘缩放；长按整块移动的自动验证来自正式Flutter手势测试。

- [手机缩放保存](/tmp/plan-drag-evidence/resized-mobile.png)
- [手机撤销恢复](/tmp/plan-drag-evidence/restored-mobile.png)
- [桌面缩放保存](/tmp/plan-drag-evidence/resized-desktop.png)
- [桌面撤销恢复](/tmp/plan-drag-evidence/restored-desktop.png)

```sh
flutter build web --no-pub --release --no-wasm-dry-run \
  --target .dart_tool/plan_drag_preview.dart \
  --output /tmp/countdown-plan-drag-preview
```

构建通过，日志 `/tmp/plan_drag_preview_build.log`。合成预览入口位于忽略目录，不纳入交付源码。

## 验证边界

未运行全仓分析／全仓测试或正式发布构建。没有连接Android／iOS实机，未验收实机触摸手感、真实跨设备同步或系统日历回写；浏览器手机尺寸不等同实机。条件校验只能保护已同步到本地的最新记录，不能锁住其他设备尚未同步的修改。

没有新增依赖、数据库字段、迁移、后端接口、系统权限或AI调用。本轮未执行提交、推送、发布或部署命令，未重置、暂存其他功能改动。

用户已确认第五轮通过，继续准备第六轮完整方案；批准前不实施第六轮代码。
