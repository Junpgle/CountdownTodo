# 第三轮：漏做规划重新安排验收

日期：2026-10-09（北京时间）。本轮实施此前用户回复“同意”的方案；先前被第二轮修复打断，此次补齐。状态：本地验收通过，等待用户确认；尚未开始第四轮。

## 交付行为

- 首页今日规划：漏做条目可以展开，即使没有专注记录；展开后有“重新安排”。
- 规划统计：真实漏做行有“重新安排”；超过十项提供“查看全部漏做”，仅展示当前统计范围，列表懒构建。虚拟课程／旧待办映射不提供恢复按钮。
- 规划日视图：漏做块的编辑器有“重新安排”，旧弹层完成关闭后再打开新面板；全天一屏拖动新建保持。
- 三个入口共用当前账号读取、来源资格检查和新建流程。同一来源忙时不重复打开。
- 草稿锁定原具体待办实例，显示原日期和时段；默认今天并展开查找，支持今天／明天／其他日期。继承有效的原计划时长，而非减去实际专注。旧无效配置有默认值和可见提示。
- 备注、提前提醒、单轮番茄、轮数带入可修改。继续采用并排设置、默认五个候选、3／5／8选择、可编辑午休／午餐／晚餐和自定义避让。
- 只在用户显式保存时新建，保留原漏做行和计数。新 UUID、manual 来源、planned 状态、零实际专注，不复制旧日历身份、番茄记录、版本或设备身份。待办本体和重复规则不变。
- 已有未结束的后续规划先展示日期时段，可以查看已有规划或明确“仍新建一次”；正在专注时只提供查看当前专注。确认只授权已展示的安排集合。
- 保存前出现新的／改动的后续规划会拒绝，保留输入；“查看最新安排”允许核对并重新明确确认。原漏做来源发生任何字段变动、完成／删除／冲突的待办、账号切换或过期截止均拒绝写入。
- 手动时间同样强制读取实际占用与截止，并遵守当前避让偏好。手机日历失败停止，只有显式选择应用内模式才降级；覆盖范围可见。
- 新规划及 oplog 同一现有事务写入；事务中再次检查来源、待办、已确认安排集合、占用及设置。异常完整回滚。保存及专注失败重试沿用已保存的新 UUID；启动成功后只重试状态更新。

## 验证结果

**17个相关测试文件，163项全部通过**。新增第三轮服务测试20项、界面测试13项，使用隔离真实 SQLite 和模拟平台桥；另外回归第二轮推荐、拖选、实际记录、日历、截止、冲突及共享弹层行为。日志：`/tmp/cdt_recovery_all_tests.log`。

关键证据：

| 场景 | 结果 |
| --- | --- |
| 45分钟漏做 → 新规划 | 原记录序列化内容与待办行逐字段不变；新 UUID、最新待办标题；45分钟、备注、提醒和番茄继承；旧实际专注／日历／记录／版本／设备字段不进入新规划 |
| 三个正式入口及统计全部列表 | 实际组件进入同一新建恢复草稿；范围外漏做不在全部列表；关闭规划／oplog零写入 |
| 查找并选用后取消 | 零写入，零专注启动；不会擅自采用第一个候选 |
| 连击／专注重试 | 只新建一次；第一次启动失败复用新 UUID，第二次启动成功但状态失败时只重试状态，不重复启动 |
| 来源、待办与账号变化 | 修改、完成、冲突、软／硬删除、重复实例替换、账号切换均阻止无效保存 |
| 保存前新增安排 | 即使区间不冲突也拒绝未展示安排；保留备注；重新查看并明确确认后更新授权集合 |
| 事务保护 | 强制读后、写事务前修改来源或插入未展示安排均拒绝；oplog插入故障回滚新规划 |
| 手动区间 | 课程占用、午休偏好、跨出单日、精确截止、日期截止、午夜和时间流逝均按规则校验 |
| 手机日历 | 读取失败拒绝；明确应用内模式放行；原有全天及跨天不占用回归通过 |
| 布局 | 320／390窄屏、1280桌面、横屏844×390、1.6字号、键盘120、浅／深色和标准／玻璃均可操作无溢出 |

执行命令：

```sh
flutter test --no-pub test/services/missed_plan_recovery_service_test.dart test/widgets/missed_plan_recovery_flow_test.dart test/services/plan_availability_service_test.dart test/services/plan_availability_repository_test.dart test/services/plan_execution_repository_test.dart test/services/device_calendar_read_service_test.dart test/services/device_calendar_refresh_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/plan_execution_view_test.dart test/widgets/device_calendar_event_detail_screen_test.dart test/widgets/course_month_view_device_calendar_test.dart test/widgets/device_calendar_home_schedule_test.dart test/services/schedule_conflict_service_test.dart test/services/calendar_sync_service_test.dart test/models/todo_time_semantics_test.dart test/widgets/app_dialogs_test.dart --reporter expanded
```

10个改动源码／测试文件 `flutter analyze --no-pub` 无问题（`/tmp/cdt_recovery_analyze.log`）；7个独立或完整维护的Dart文件格式检查零变化，旧复杂文件仅改相关区域；`git diff --check`通过。

## 视觉证据及边界

预览复用正式共享编辑器和空闲算法，数据全部合成，保存只发生在预览内存；正式三个入口和保存数据保护由隔离SQLite测试覆盖。

- [手机重新安排界面](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/missed-plan-recovery/recovery-mobile.png)
- [原配置继承与并排设置](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/missed-plan-recovery/inherited-settings-mobile.png)
- [显式保存成功提示](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/missed-plan-recovery/saved-new-plan-mobile.png)

已编译并运行Web合成预览。未连接Android／iOS实机；未验证真实日历提供方、原生通知、真实专注启动或手机触摸手感。没有运行全仓测试或发布构建，不承诺锁住其他设备／系统日历中尚未同步的更新。

本轮没有新增依赖、数据库迁移、后端或权限变更；未修改个人业务数据，未提交、推送、发布或部署。费用单价、搜索、语音及其他在途改动保留，未编辑其实现文件。
