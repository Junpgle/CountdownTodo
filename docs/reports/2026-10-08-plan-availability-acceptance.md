# 第二轮验收：规划块可用时段推荐

验收日期：2026-10-08。用户已批准“同意第二轮”。
状态：功能、反馈修复与界面重设计完成；用户于2026-10-08确认“可以，继续下一轮”，第二轮验收通过。第三轮处于方案审批阶段，尚未实施。

后续按用户外观反馈完成[界面重设计验收](2026-10-08-plan-availability-ui-redesign.md)。本文保留重设计之前的截图与记录；当前外观和预览地址以新报告为准。

## 交付结果

“添加／编辑规划块”中加入“找可用时间”，连接当前账号课程、固定日程、规划及兼容旧执行区间，按时长和当天窗口推荐最多三个连续空档。Android/iOS 已开启且已授权的手机日历也纳入；其他平台明确只检查应用内安排。

课程调休、假期和多学期沿用原服务。跨日固定日程／规划、全天及瞬时手机事件有专门覆盖。日期／定时截止限制候选结束；今天向上对齐分钟。选择只填草稿，保存才写规划和 oplog；失败保留草稿，不启动专注。保存前强制复读手机事件并在本地事务核对占用、账号、待办、编辑版本，保留旧记录实际执行与日历元数据。

点击新增、拖选新增、编辑已有块统一使用提取后的正式 `PlanBlockEditorSheet`。异步请求和历史估时不会覆盖后续选择；重复点击不重复创建。专注启动失败复用已保存规划，启动成功但状态写入失败时只重试状态。

## 本轮反馈与修复

用户反馈“空闲时段很多，但就是找不到空闲”，并确认显示“当天没有连续…分钟的可用时段”。

合成数据复现出两类假占用：跨多天的截止待办被视为全程执行，以及 `created_date = 0` 被视为从 1970 年起连续执行。物理创建时间兜底同样不能证明实际执行区间。修复后遵循现有规划日历的同日旧执行区间投影，保留真实同日区间，排除这些假预约，不迁移或改写原待办。

回归测试先在修复前失败（存在两条假占用），修复后返回 08:00–08:45，并能完成真实隔离数据库保存。另覆盖创建时间锚点与真实旧执行区间共存，后者仍占用 09:00–10:00。此为已复现的错误类型；没有读取用户个人业务记录，不能宣称已确认其具体记录就是这两类。

界面新增“已计入 N 项占用”可展开明细，显示来源和实际时段；手机事件不显示标题／地点。显示目标截止，受截止压缩而无候选时明确提示“截止前没有连续…分钟”。占用明细只展示前 50 项，全部记录均参与计算。

补验玻璃弹层时发现底部 16px 溢出：包内弹层另有 16px 头部、24px 尾部，而原编辑器只留出 24px。编辑器现在按实际弹层类型扣除外部占位，再进行滚动布局。标准／玻璃组合复验通过。

## 执行的验收

最终一次运行：**91 项测试全部通过**（9 个聚焦／回归文件）。

| 场景 | 证据和结果 |
| --- | --- |
| 精确推荐及边界 | 45 分钟示例返回 08:00、10:00、12:00；重叠、包含、相邻、空集合、恰好容纳、非法区间和满日占用通过 |
| 课程与状态 | 真实隔离四表；调休／假期／多学期、跨日固定安排／规划、规划状态、只排除自身 UUID、未确定时间提示通过 |
| 待办时间语义 | 截止点／日期待办不占一天；日期截止、时间截止、过去时间、旧区间去重和假占用反馈回归通过 |
| 来源和账号 | 两个合成账号不混读／写；删表、损坏规则不降级为假空闲；其他账号损坏设置不干扰本账号 |
| 手机日历 | 模拟 MethodChannel 验证跨午夜、全天、瞬时、平台守卫、缓存复用、强制复读和旧请求不得污染新缓存 |
| 隐私 | 外部标题和事件 ID 不进入规划 oplog；所有样本均为合成数据 |
| 异步 | 日期 A→B→A、改时长／待办、关闭、相关刷新、日历设置、恢复前台和晚估时不会覆盖新状态 |
| 采用／取消／保存 | 实际共享编辑器配真实隔离 SQLite：采用取消零规划／oplog 写入；显式保存一条规划和一条 oplog |
| 保存并发 | 新占用、待办完成、状态／版本变动、事务失败和重复 UUID 均拒绝或回滚；双击不重复创建；元数据不丢 |
| 专注 | 保存校验失败零启动；成功后才启动；启动失败重试不再创建；状态写入失败重试零重复启动（控件测试注入启动回调） |
| 三个真实入口 | 用完整 `TodoPlanScreen` 和隔离 SQLite 进行点击、拖选、点已有块；均打开正式共享编辑器和推荐入口，取消未写入规划 oplog。使用未来合成日期避免页面既有漏做标记干扰 |
| 布局 | 正式 `showAppModalBottomSheet`：320×640/字体1.6/键盘260；390×844/字体2/深色；720×360/字体1.6/键盘130/深色；1280×900/字体2；各组合玻璃开／关，采用和保存可达且无溢出 |
| 既有功能回归 | schedule_conflict、calendar_sync、todo_time_semantics、app_dialogs 原有测试通过 |

聚焦静态分析覆盖本轮 16 个源码／测试路径：**No issues found**。
11 个新增源码／测试文件的 `dart format --output=none --set-exit-if-changed` 检查无变更；老文件新增方法单独经 formatter 格式化，避免重排其他代码。
`git -c core.fsmonitor=false diff --check` 通过。

执行的主要命令：

```bash
flutter test test/services/plan_availability_service_test.dart test/services/plan_availability_repository_test.dart test/services/device_calendar_refresh_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart test/services/schedule_conflict_service_test.dart test/services/calendar_sync_service_test.dart test/models/todo_time_semantics_test.dart test/widgets/app_dialogs_test.dart --reporter expanded
flutter analyze lib/models/plan_availability.dart lib/services/plan_availability_service.dart lib/services/plan_availability_repository.dart lib/services/device_calendar_read_service.dart lib/widgets/plan_availability_panel.dart lib/widgets/plan_block_editor_sheet.dart lib/screens/todo_plan_screen.dart lib/storage_service.dart lib/storage_service_contract.dart lib/storage_service_fixed.dart test/services/plan_availability_service_test.dart test/services/plan_availability_repository_test.dart test/services/device_calendar_refresh_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart test/support/plan_availability_fixture.dart
flutter devices
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8944 -t .dart_tool/plan_availability_preview.dart
```

没有执行整个仓库所有测试、整个仓库分析、release 构建、部署或真机完整应用验收。

## 可见预览与证据

浏览器预览运行正式共享编辑器和正式标准／玻璃弹层，来源为合成样例。浏览器保存只存在预览内存，真实持久化由上述隔离 SQLite 控件测试另行验证。没有把浏览器演示当作真实原生日历或通知验收。

- 标准桌面：查询45分钟，采用10:00–10:45，显式保存后显示“已保存1次”。
- 320窄屏、深色、字体1.6：可读候选、来源与占用明细；采用后取消，仍只保存1次。
- 最终玻璃1280×900：通过拖选新增共用编辑器得到同样三条候选，保存10:00–10:45后仍明确显示1次；没有错误日志。临时 viewport 已恢复，最终预览保留在 127.0.0.1:8944。

证据目录：`/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-availability`。包含最终测试／分析日志、修复前回归失败日志、玻璃布局日志及截图。

![最终玻璃弹层候选](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-availability/final-glass-candidates.png)

![窄屏候选](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-availability/mobile-320-dark-1.6.png)

![最终显式保存结果](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-availability/final-glass-saved.png)

## 成本、范围与限制

1000 条合成占用的一次最终测试观察：四表完整快照读取 **13.205ms**，纯计算 **1.690ms**。这是隔离测试的单次观察，不是性能保证。

当前推荐一次完整读取课程、待办、固定日程、规划四表，再按本地查询日筛选／裁剪。没有 SQL 分页或性能提升比例承诺。保存执行新快照、课程准备与事务内最新快照；正常保存路径约 13 次本地读取（含目标规划版本读取）和2次写入，不含首次数据库初始化或其他同步／专注动作。手机日历强制刷新可能增加提供方查询，未声称跨端原子预订。

`flutter devices` 仅发现 macOS、Chrome，无 Android/iOS 设备。手机日历证据来自模拟桥接；实际原生授权／提供方、系统通知、勿扰和完整专注启动未真机验证。源码中保留原平台守卫与启动服务。

本轮没有新增业务表／字段、依赖、后端、权限或平台端点；没有 commit、push、部署、发布。工作区包含第一轮以及其他未提交／并行变更；仅本轮规划、读取、条件保存、测试白名单和文档属于这里的交付。

下一步等待用户复验本轮。若仍出现无候选，可根据界面占用明细、日期／时长／窗口及截止继续定位；用户确认没问题后才提交第三轮完整方案，再等待批准实施。
