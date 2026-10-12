# 第十二轮验收：完成待办后的剩余规划收尾

日期：2026-10-12（北京时间）。本轮实现与针对性自动验证已完成，等待用户验收。版本为 `6.7.10`。提交仅在本地创建；未推送、发布或部署。

方案：[完成待办后的剩余规划收尾](../proposals/2026-10-11-completed-todo-plan-cleanup.md)。

## 实现

- 已完成待办可以从待办编辑页入口或「待规划」页菜单打开收尾列表。列表支持搜索、文件夹筛选和分页；详情只选择已展示的合格规划，展示投入、提醒、团队和手机日历提示。
- 批量取消在一个 SQLite 事务内复核账号、待办、规划集合、状态和投入，规划与 oplog 一起写入或一起回滚。重复提交只对本请求的完整已保存结果幂等，不重复递增版本或写日志。
- 修复了成功取消但响应丢失后的边界：用户在规划开始时间之后重试时，完整匹配的本次取消仍能识别为成功；其他安排仍按当前时间与最新数据重新复核。
- 取消后更新应用提醒来源；失败提供单独重试。取消状态不会被稍后排队的旧提醒更新复活，番茄和习惯提醒保持独立。手机日历副本不会被本次操作删除，界面对此明确说明。
- 未改数据库结构、后端接口或同步字段。

## 自动验证

- `flutter test --no-pub test/services/plan_cleanup_repository_test.dart --reporter expanded`：28项通过，覆盖资格、并发变化、分页、事务故障回滚、取消重试和旧提醒保护。
- `flutter test --no-pub test/services/scheduled_reminder_registry_test.dart --reporter expanded`：3项通过，覆盖来源隔离及取消规划过滤。
- `flutter test --no-pub test/widgets/plan_cleanup_screen_test.dart --reporter expanded`：1项通过，覆盖确认、手机日历边界、提醒失败和不重复写入的提醒重试。
- `flutter test --no-pub test/widgets/plan_cleanup_flow_test.dart --reporter expanded`：10项通过，覆盖取消零写入、并发新增、响应丢失重试、分页上限、团队只读、身份变化、入口读取错误和窄屏／桌面布局。
- `flutter test --no-pub test/widgets/plan_backlog_screen_test.dart test/widgets/todo_edit_plan_entry_test.dart test/services/todo_notification_policy_test.dart --reporter expanded`：29项通过，检查待规划与待办编辑入口及既有提醒策略。
- 针对本轮源文件和测试运行 `dart analyze`：`No issues found!`。
- `flutter build web --no-pub --output /tmp/countdown-plan-cleanup-web-final --no-web-resources-cdn`：正式 Web 入口构建成功。
- `git diff --check`：提交前执行，通过。

## 验收边界

本轮没有做浏览器手工走查、原生手机系统通知／日历验证或多设备同步验证。Widget 测试使用合成 SQLite 和提醒回调，不代表 Android、iOS、桌面通知插件或外部日历已实机验证。没有运行全仓测试或全仓分析。

本轮功能提交：`b1b6831d`（事务取消与提醒保护）、`8cb26551`（收尾界面、入口与版本号）。方案和报告随文档批次提交。未推送、发布或部署。
