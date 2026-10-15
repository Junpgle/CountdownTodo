# 第四轮：规划冲突检查与快捷改期验收

日期：2026-10-09（北京时间）。用户回复“你来继续做这个第四轮”后恢复实施。状态：相关本地验收通过；用户已回复“通过，继续准备第五轮方案”。第五轮后续已批准实施，见对应方案和验收报告。

## 交付行为

- 首页今日规划与规划日视图增加紧凑冲突入口，数量按真实规划UUID去重；没有重叠时隐藏，读取失败或时间待定显示未完成。
- 列表支持所选日期、今天、未来七个本地日期，按日期分组，展开显示每个来源及精确重叠区间。进入、数据变化、前台恢复、日期切换及当前冲突规划结束时重新检查；没有后台轮询。
- 共用可用时段的实际课程调休、固定日程、规划和旧执行时段规则。范围读取共用一次本地来源快照和一次手机日历查询。相邻区间不重叠，只排除自身UUID；同一待办其他规划仍参与检查。
- 全天及跨本地日期手机日历不占用；专注、时间日志和避让偏好不冒充已保存预约。过去日期、已结束以及完成／漏做／跳过／取消规划不产生待改期提醒。
- 课程、固定日程、旧待办、手机日历可以查看来源详情。另一规划采用独立只读详情，避免打开旧日视图时自动维护漏做状态产生写入。专注中的规划只提供查看当前专注。
- 调整安排在列表完全关闭后进入整页编辑器，锁定原待办，继承原时长、备注、提醒与番茄配置。先展示两个推荐，自定义条件放在查找弹窗，保留五个候选、3／5／8数量和账户避让偏好；用户自行选择时段并保存。
- 保存更新原UUID，保留实际专注、记录关联、设备及日历身份。推荐与手动时间均强制检查最新占用、截止、时间和避让，事务中复查账户、待办、原记录全部内容及占用，规划与oplog同一事务写入。失败保留输入，取消和查看零写入。
- 全天24小时一屏、拖动新建、移动／缩放保持现有路径。没有依赖、数据库结构、后端协议、原生权限、通知或AI调用变更。

## 自动验证

**21个相关测试文件，251项全部通过**；其中第四轮新增服务29项、界面21项，共50项。使用隔离SQLite、模拟平台桥及可控时钟，没有读取或修改个人业务数据。

| 验收项目 | 证据 |
| --- | --- |
| 多来源和数量 | 一条规划多个来源只计一次；规划对规划双向显示，来源去重，半开边界、自身排除、跨日逐日裁剪与七天范围正确 |
| 来源覆盖 | 同日定时手机事件含来源标题；全天及跨日期事件排除；七天只查询一次手机日历；日历失败不返回假空闲，明确点击才降级；时间待定仍显示未完成 |
| 入口与详情 | 正式首页／日视图入口进入同一列表；课程／固定日程／旧待办／手机日历／另一规划进入对应详情；关闭及查看零oplog，规划表不变 |
| 时间与刷新 | 新日期结果不被旧请求覆盖；今天／未来七天在前台跨午夜自动换日；后台不发定时读取；固定日程变化清除自然消失的提示，不保存处理标记 |
| 改期与取消 | 整页编辑器锁定待办，展示两个推荐；查找、选择候选后取消零写入；显式保存只更新原UUID，其他规划和待办逐字段不变，实际及日历身份保留 |
| 保存保护 | 原时间冲突、其他同待办规划、截止和避让变化阻止保存；账户切换、待办完成／删除／冲突、原记录状态或内容变化均拒绝；备注等输入保留 |
| 事务与重试 | 最终读取后出现新占用或避让变化在事务内拒绝；oplog故障完整回滚；专注状态重试复用已保存原UUID和时间 |
| 布局及既有行为 | 320／390窄屏、720×360短屏、1280桌面，1.6／2.0字号、键盘、深浅色、普通／玻璃布局可操作无溢出；回归空闲推荐、第三轮恢复、拖选与实际记录、日历、共享弹层 |

测试命令：

```sh
flutter test --no-pub \
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

日志：`/tmp/plan_conflict_final_tests.log`。9个相关源码／测试文件静态分析无问题：

```sh
flutter analyze --no-pub \
  lib/models/plan_availability.dart \
  lib/services/plan_availability_repository.dart \
  lib/services/plan_conflict_review_service.dart \
  lib/widgets/plan_conflict_review.dart \
  lib/widgets/plan_block_editor_sheet.dart \
  lib/widgets/plan_block_today_section.dart \
  lib/screens/todo_plan_screen.dart \
  test/services/plan_conflict_review_service_test.dart \
  test/widgets/plan_conflict_review_test.dart
```

日志：`/tmp/plan_conflict_analyze_final.log`。7个独立维护Dart文件格式检查零变化；两个旧大型界面文件仅修改相关区域。`git diff --check`通过。

## 浏览器视觉验收

正式列表、入口组件、整页编辑器及本地空闲算法在Web合成预览中运行；保存只更新预览内存。预览构建命令：

```sh
flutter build web --no-pub --release --no-wasm-dry-run \
  --target .dart_tool/plan_conflict_preview.dart \
  --output /tmp/countdown-plan-conflict-preview
```

构建通过，日志 `/tmp/plan_conflict_preview_build.log`。桌面1280×720及手机尺寸390×844已实际检查：两条规划重叠，展开显示高数与阅读19:00–19:30、与小组讨论19:30–19:45的精确交集；进入整页调整高数，保留45分钟及备注／番茄配置，自行选08:00–08:45再保存后，返回首页原两条规划仍在，重叠提示消失。

- [桌面冲突来源](/tmp/plan-conflict-review-evidence/conflicts-desktop.png)
- [手机冲突列表](/tmp/plan-conflict-review-evidence/conflicts-mobile.png)
- [手机整页改期及两个推荐](/tmp/plan-conflict-review-evidence/adjust-mobile.png)
- [保存后的合成首页](/tmp/plan-conflict-review-evidence/saved-mobile.png)

## 验证边界与后续

未运行全仓测试／全仓分析或正式发布构建。没有连接Android／iOS实机，真实手机日历提供方、原生通知、真实专注启动及触摸拖动手感仍待设备验收；模拟平台桥与浏览器手机尺寸不等同实机。检查是本地快照，不能锁住其他设备或尚未同步的系统日历变更。

本轮未执行提交、推送、发布或部署。期间工作树已有外部提交，最终按当前文件核对；未重置这些提交或其他功能。用户已确认第四轮通过，后续提交第五轮完整方案供审批，批准后实施。
