# 第八轮：规划复盘与真实投入明细验收

日期：2026-10-11（北京时间）。用户回复“确认”批准[完整方案](../proposals/2026-10-11-plan-review.md)。状态：实现和本地验收完成；用户于2026-10-11回复“通过，准备第九轮方案”，本轮验收通过。

## 交付结果

- 在原“规划统计”入口完成日／周／月概览、趋势、具体待办投入排行和独立明细页；首屏50项、加载更多，保持筛选。快照未变时，从原记录详情返回保留已加载页和滚动位置。
- 真实规划预算不再包含课程、日历或旧式待办映射。取消／跳过单列；已结束规划按finished状态计算完成情况，尚未结束不进入分母；不在统计页按80%重新推断完成，不改原专注业务状态转换。
- 实际专注只取已结束、有效、无冲突记录的非负实际秒数。零秒保留；缺失或坏时长单列，行内显示“时长待核对”，不伪装成0分钟，也不回退到计划时长。
- 按具体UUID核对规划ID、记录ID列表与唯一同待办重叠关系。每条记录只计一次；已关联／未关联／归属待核对互斥。存在多个候选、悬空ID、矛盾身份或失效规划时不给多个规划重复分配。
- 本期记录投入、累计记录投入、原累计缓存分别展示；缓存不补入实际。时间日志按范围裁剪、合计毫秒后转秒，不与专注相加。
- 复盘提示明确为本地规则，可查看触发依据，不调用远程AI。原漏做重新安排与保存校验保留；未来的异常missed标记只供核对，不提前生成恢复提示。
- 只读SQLite仓储、关联候选范围约束、账号／成员保护、请求序号、分页失效及前台单次边界刷新完成。读取失败不显示零值成功页；旧Prefs未初始化时明确提示，不自动迁移或修复。
- 界面使用主题色，正常手机两列、桌面四列，320大字体单列；窄屏大字体使用短日期并提供完整日期提示。时间轴及其24小时一屏、拖动新建／移动／撤销未改动。

功能规则见[规划复盘说明](../features/plan-review.md)。

## 自动验收

最终33个相关测试文件共 **475项通过**，命令输出为`01:04 +475: All tests passed!`，日志：`/tmp/plan_review_final_full_regression.log`。

其中第八轮新增27项服务测试、12项Widget测试，共39项；其余为第三至第七轮相关回归。第八轮及原统计漏做入口专项52项也通过（`/tmp/plan_review_final_focused.log`）。不同批次没有累加成单次通过数。

| 验收内容 | 证据范围 |
| --- | --- |
| 规划口径 | 课程和旧式区间不混入真实预算；取消／跳过、未来和已结束分别计数；finished状态分子、零分母、坏计划时长、未来missed核对 |
| 专注唯一计数 | 显式ID与列表一致去重、同待办重叠多个候选、矛盾待办身份、悬空ID不被其他列表“救回”、没有直接待办时不猜排行归属 |
| 时长可信度 | 缺失／零／负／非法状态／冲突／删除／无结束时间，中断与切换；坏时长明细不会显示真实0分钟 |
| 范围与累计 | 前一天开始的跨午夜规划仍可关联；专注完整归开始日、次日不重复；累计与本期分离、原缓存不放大实际；31个自然日及相邻月边界 |
| 实际分类对账 | 已关联61秒、未关联62秒、待核对归属63秒，合计186秒；类别记录UUID不重复 |
| 时间日志 | 跨日裁剪、重叠不合并入专注；两个30.5秒区间先合计再得到61秒 |
| 历史与详情 | 同名不同UUID、完成待办、已删除待办标题快照；既有记录详情与标签名称；删除记录拒绝打开 |
| 分页与查询 | 105条稳定50项游标，等总量的标题写入也废弃游标；1001条无关专注及1001条无关规划附长备注，概览10次查询、每次返回少于60行，不解码完整历史或逐项查询。未宣称绝对耗时提升 |
| 身份与异步 | 账号／成员切换拒绝旧身份；旧范围请求不能覆盖新维度；失败明确、重试保留日期；打开与读取前后SQLite写次数不增加 |
| 可见流程 | 概览下钻、筛选分类、累计来源、53项加载更多及返回滚动位置、原漏做重新安排入口与取消零写入 |
| 适配与回归 | 320／390／720×360／1280×900，1.8倍字体、深浅色与玻璃设置无溢出；第三至七轮恢复、冲突、拖动撤销、空闲、估时、记录、设备日历与待规划流程回归 |

测试使用隔离数据库和合成数据。多数测试使用当前生产迁移结构；旧记录可空字段兼容用例在隔离数据库内创建历史表变体，未修改生产schema。初测日志保留于`/tmp/plan_review_initial_tests.log`、`/tmp/plan_review_service_tests.log`、`/tmp/plan_review_widgets_initial.log`，包含测试种子必填字段、历史可空结构及测试平台变量等修正过程。

最终回归使用第六轮报告列出的28个文件，加第七轮3个文件和以下第八轮2个文件；准确33文件清单保存在`/tmp/plan_review_regression_files.txt`：

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
  test/widgets/plan_review_screen_test.dart --reporter expanded
```

相关4个源码／测试文件的Dart静态分析无问题（`/tmp/plan_review_final_analyze.log`）。只格式化这4个本轮文件；暂存和未暂存差异均检查空白错误，未运行全仓格式化或全仓静态分析。

## 浏览器验收与截图

预览：[第八轮本机预览](http://127.0.0.1:8963/)。入口“规划统计”。独立合成账号`synthetic-review-20261011`，正式页面、正式读取仓储和Web SQLite；手机日历停用，现有网络服务指向本机无服务端口，不读取个人账号或日历、不调用远程AI。刷新预览会重建合成种子。

合成当天结果：真实规划270分钟；已结束5项中1项finished；已核实专注110分钟＝已关联50＋未关联35＋归属待核对25；日志90分钟单列。高数规划本期50分钟、累计60分钟、原缓存5400秒分开；月视图包含前一天10分钟，因此专注120分钟。

- [手机概览，最终构建](/tmp/plan-review-evidence/mobile-overview.png)
- [异常记录显示时长待核对，最终构建](/tmp/plan-review-evidence/mobile-issues.png)
- [320大字体深色单列](/tmp/plan-review-evidence/mobile-large-font.png)
- [桌面概览](/tmp/plan-review-evidence/desktop-overview.png)
- [整月概览与逐日趋势](/tmp/plan-review-evidence/desktop-month.png)
- [专注记录三种关联入口](/tmp/plan-review-evidence/mobile-focus.png)
- [歧义关联仅计一次](/tmp/plan-review-evidence/mobile-attribution.png)
- [规划本期、累计和原缓存来源](/tmp/plan-review-evidence/mobile-plan-source.png)
- [累计记录包含前一天](/tmp/plan-review-evidence/mobile-lifetime.png)
- [原专注详情保留学习标签](/tmp/plan-review-evidence/mobile-record-detail.png)

浏览器先在8961验证分类与详情流程，再在8962复核单列大字体与月视图，最终8963核对异常时长文案和概览；截图按对应阶段保存，前两轮证据不冒充最后一次构建截图。浏览器实测发现并修正两处显示问题：320大字体两列挤碎时长、坏时长行显示0分钟。两项均已加入最终自动回归断言。

最终Web构建成功（`/tmp/plan_review_final_web_build.log`，50.5秒）：

```sh
flutter build web --no-pub --target .dart_tool/plan_review_preview.dart \
  --output /tmp/countdown-plan-review-preview --pwa-strategy=none \
  --no-web-resources-cdn
```

预览入口在忽略的`.dart_tool/`，构建产物位于`/tmp/`，未加入发布应用。构建的Wasm预检及弃用提示不等同于Wasm或原生平台验收。

## 后续复核修正

验收后复核发现两项展示边界：坏时长明细原先显示“0分钟”，以及结束时间在未来的时间日志可能被算入记录时长。坏时长行现显示“时长待核对”；未来结束的日志进入核对列表，统计不计其时长，并在结束时刷新。补录编辑器也不允许保存未来结束时间。

在隔离SQLite中复现了未来日志提前计入3600秒；修复后新加的未来日志回归断言检查概览、分页明细、核对列表及结束时刻刷新边界。当前规划复盘服务与Widget专项共40项通过，相关3个Dart文件分析无问题。原475项全回归结果来自上述修正之前；修正后未重跑整套33文件回归。

## 边界与后续

未运行全仓测试，未验证Android／iOS／macOS／Windows实机、真实账号长时间使用和多设备同步。Web合成预览及Widget测试不能代替原生玻璃渲染、系统键盘、时区设备或权限验收。本轮没有改数据库结构、后端、同步协议、系统权限或专注计时；番茄统计及个人报告保留原算法，旧记录兼容口径差异已在界面说明。

本执行未调用Git暂存、提交、推送或部署。共享工作区期间观察到外部提交`d2d74aa5`及其他任务变更，保留其状态；最终文案、测试与验收报告可能仍有未提交变更，不能把外部提交等同于本执行发布。

用户已确认第八轮验收通过。下一步仅提交[第九轮完整方案](../proposals/2026-10-11-plan-editor-drafts.md)，批准后再实施。
