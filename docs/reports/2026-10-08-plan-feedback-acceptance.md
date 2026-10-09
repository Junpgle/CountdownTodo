# 规划反馈修复与灵活推荐验收

日期：2026-10-08。范围：用户追加的第二轮修复及布局、推荐规则优化。第三轮“漏做规划重新安排”已经批准，仍保留原方案；本次按用户最新指示优先调整第二轮。

## 已交付行为

| 项目 | 当前行为 |
| --- | --- |
| 手机日历跨天事项 | 按本地日期判断跨天，含今天08:00到明天08:00。统一按全天信息展示，不计入空闲查询或保存时的占用；仍保留原始开始、结束与日期覆盖。真正同日定时事项继续占用。 |
| 规划实际信息 | 时间轴新增专注、时间日志独立展示区，含未关联规划的记录；可打开当天列表和既有详情。跨午夜记录按当天相交部分展示，详情保留完整日期。 |
| 拖动新建 | 全天24小时一屏，无纵向滚动容器。空白处点击／拖选仍打开共享编辑器，已有规划保留编辑入口；实际记录只读，拖动不会新建规划。 |
| 其他设置 | 宽屏三列、手机两列，极窄宽度一列。保留单轮时长、轮数和提前提醒；移除“AI帮我安排更多”按钮。 |
| 候选数量 | 默认最多5个，可切换3／5／8。先覆盖不同空档，再用长空档内的后续、不重叠时段补充，按开始时间排序；不足时按真实数量显示。 |
| 午休与用餐避让 | 午休12:00–14:00、午餐11:30–12:30、晚餐18:00–19:00分别可开关，默认关闭；均可改时间，也能新增、关闭或移除自定义时段。偏好只作用于当前编辑器，不创建额外日程。 |
| 保存校验 | 避让范围和真实占用共同约束查找及最终保存。修改范围或数量使已采用推荐失效，需重新查找。原账号、来源刷新、版本、截止及重复操作保护继续有效。 |

实际记录只用于展示和既有专注关联计算。时间日志不会冒充专注，也不会转成规划；旧日志和专注缓存继续走现有迁移路径。新增日志和专注记录触发对应刷新，规划页无需重进。读取错误有重试入口。

## 验证

最终15个测试文件：**129项全部通过**（`/tmp/cdt_plan_all_final_tests.log`）。覆盖：

- 隔离真实SQLite中跨午夜、边界、删除、空标签、旧缓存、账号切换及读取失败；查看实际记录不创建规划或oplog，日志保存即时刷新。
- 手机全天／跨天事项在今天和明天不占用；同日定时事项仍阻挡保存，午夜前瞬时提醒不误判全天，强制读取及外部信息不持久化。
- 全天一屏、正式页面空白处拖选、实际记录拖动只读、旧点击／拖选／编辑三入口。
- 默认五个、可调数量、空档优先与长空档补充、重叠午休用餐合并、边界相邻、全日避让、不足时长和无效范围。
- 避让冲突保存拒绝且零规划／oplog；规则变化使已采用推荐失效；自定义添加／移除及取消保留输入。
- 并排控件几何、AI按钮移除；320/390/720/1280宽度、大字体、键盘、普通／玻璃模式；短屏避让时间对话框可操作。
- 既有推荐、截止、设备日历刷新、日历同步、冲突、保存重试和对话框回归。

执行命令：

```sh
flutter test --no-pub test/services/plan_availability_service_test.dart test/services/plan_availability_repository_test.dart test/services/plan_execution_repository_test.dart test/services/device_calendar_read_service_test.dart test/services/device_calendar_refresh_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/plan_execution_view_test.dart test/widgets/device_calendar_event_detail_screen_test.dart test/widgets/course_month_view_device_calendar_test.dart test/widgets/device_calendar_home_schedule_test.dart test/services/schedule_conflict_service_test.dart test/services/calendar_sync_service_test.dart test/models/todo_time_semantics_test.dart test/widgets/app_dialogs_test.dart --reporter expanded
```

17个相关源码／测试文件 `flutter analyze --no-pub`：**无问题**（`/tmp/cdt_plan_all_final_analyze.log`）。新增／独立改动的14个Dart文件格式检查无变化；`git diff --check`通过。旧复杂文件仅修改相关片段，保留工作树内其他改动。测试、编译和视觉截图为独立证据，不混同。

## 界面证据与边界

预览使用正式共享编辑器和正式实际记录控件，数据全部合成，保存仅在预览内存。正式规划页使用隔离SQLite的widget测试验证；预览截图不表示手机实机验收。

手机宽度截图：

- [并排设置](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-feedback/settings-mobile.png)
- [午休与用餐组合避让](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-feedback/avoidance-mobile.png)
- [五个推荐时段](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-feedback/five-recommendations-mobile.png)
- [实际记录列表](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-feedback/records-mobile-light.png)

未连接Android/iOS实机，因此未验证真实手机日历提供方及触摸手感。未执行发布、提交、推送、后端改动或全仓测试；本次代码没有新增依赖、数据库字段或权限。工作树中其他任务的语音功能、依赖及平台变更不属于本次范围，均予保留。
