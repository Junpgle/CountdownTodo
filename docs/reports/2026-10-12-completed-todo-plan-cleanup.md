# 第十二轮验收：完成待办后的剩余规划收尾

日期：2026-10-12（北京时间）。本轮实现与针对性自动验证已完成，用户于当日回复「通过」，**用户验收通过**。本报告原始实现版本为 `6.7.12`，后续补充见关联报告。提交仅在本地创建；未推送、发布或部署。

方案：[完成待办后的剩余规划收尾](../proposals/2026-10-11-completed-todo-plan-cleanup.md)。

使用说明：[已完成待办的剩余规划收尾](../features/plan-cleanup.md)。

## 实现

- 已完成待办可以从待办编辑页入口或「待规划」页菜单打开收尾列表。列表支持搜索、文件夹筛选和分页；详情只选择已展示的合格规划，展示投入、提醒、团队和手机日历提示。
- 批量取消在一个 SQLite 事务内复核账号、待办、规划集合、状态和投入，规划与 oplog 一起写入或一起回滚。重复提交只对本请求的完整已保存结果幂等，不重复递增版本或写日志。
- 修复了成功取消但响应丢失后的边界：用户在规划开始时间之后重试时，完整匹配的本次取消仍能识别为成功；其他安排仍按当前时间与最新数据重新复核。
- 取消后更新应用提醒来源；失败提供单独重试。只有待执行、已延后和已提醒规划保留开始提醒；专注中、已漏做、已结束、已取消及已跳过状态会被过滤。稍后排队的旧提醒更新不能复活取消状态，番茄和习惯提醒保持独立。无规划 ID、空白 ID 和数据库中不存在的规划提醒也会被丢弃，手机日历副本不会被本次操作删除，界面对此明确说明。
- 收尾列表的规划选择框提供日期、时段、投入分钟和处理原因的语义标签；关联团队待办的剩余规划仍为只读，其「查看详情」按钮保持独立可访问。
- 未改数据库结构、后端接口或同步字段。

## 自动验证

- `flutter test --no-pub test/services/plan_cleanup_repository_test.dart --reporter expanded`：30项通过，覆盖资格、并发变化、分页、事务故障回滚、取消重试、所有规划状态的提醒白名单，以及无效规划 ID 过滤。
- `flutter test --no-pub test/services/scheduled_reminder_registry_test.dart --reporter expanded`：3项通过，覆盖来源隔离及取消规划过滤。
- `flutter test --no-pub test/widgets/plan_cleanup_screen_test.dart --reporter expanded`：1项通过，覆盖确认、手机日历边界、提醒失败和不重复写入的提醒重试。
- `flutter test --no-pub test/widgets/plan_cleanup_flow_test.dart --reporter expanded`：10项通过，覆盖取消零写入、并发新增、响应丢失重试、分页上限、团队只读及其可访问详情按钮、身份变化、入口读取错误和窄屏／桌面布局。
- `flutter test --no-pub test/widgets/plan_backlog_screen_test.dart test/widgets/todo_edit_plan_entry_test.dart test/services/todo_notification_policy_test.dart --reporter expanded`：29项通过，检查待规划与待办编辑入口及既有提醒策略。
- 针对提醒守卫、收尾界面和对应测试运行 `dart analyze`：`No issues found!`。
- `flutter build web --no-pub --output /tmp/countdown-plan-reminder-ids-web --no-web-resources-cdn`：正式 Web 入口构建成功，包含规划提醒 ID 校验和收尾列表语义标签。
- `git diff --check`：提交前执行，通过。

## 验收边界

浏览器手工流程、窄屏大字体截图及50文件相关回归已补充，详见[浏览器与相关回归补充验收](2026-10-12-plan-cleanup-browser-acceptance.md)。原生手机系统通知／日历及多设备同步尚未实机验证；Widget和Web提醒注册表结果不代表这些平台已经验证。没有运行全仓测试或全仓分析。

本轮功能提交：`b1b6831d`（事务取消与提醒保护）、`8cb26551`（收尾界面、入口与版本号）、`f9af5771`（规划状态提醒白名单）、`4df26ecc`（有效规划提醒引用过滤）、`c7e558f1`（收尾列表无障碍语义）。方案、使用说明和报告随文档批次提交。未推送、发布或部署。
