# screens/ — 页面层

最后更新：`2026-05-24`

## 目录定位

`screens/` 包含全屏页面、功能页和功能专属子目录。跨页面复用的展示组件应放在 `lib/widgets/`。

## 主要页面

| 文件 | 职责 |
|------|------|
| `home_dashboard.dart` | 主仪表盘：待办、倒数日、课程、番茄钟、规划块、屏幕时间、同步信号。 |
| `login_screen.dart` | 登录/注册、服务器选择、迁移入口。 |
| `splash_screen.dart` / `default_splash_screen.dart` | 启动页和默认启动页。 |
| `add_todo_screen.dart` | 手动创建待办和解析辅助创建。 |
| `todo_chat_screen.dart` | AI 待办助手 UI 和 action 确认。 |
| `todo_confirm_screen.dart` | 解析结果确认。 |
| `todo_plan_screen.dart` | 规划块日视图、点击/滑动创建、编辑、移动、调整边缘、开始番茄钟。 |
| `plan_block_stats_screen.dart` | 规划块统计。 |
| `pomodoro_screen.dart` | 番茄钟页面外壳，子视图在 `screens/pomodoro/`。 |
| `time_log_screen.dart` / `time_log_components.dart` | 时间日志页面和专用组件。 |
| `course_screens.dart`、`course_month_view.dart`、`course_calendar_adjustment_screen.dart` | 课程表视图和日历调整。 |
| `conflict_inbox_screen.dart` | 冲突中心。 |
| `team_management_screen.dart`、`team_announcement_screen.dart`、`team_message_center_screen.dart` | 团队协同页面。 |
| `personal_timeline_screen.dart`、`medal_wall_page.dart` | 个人时间线和勋章相关页面。 |
| `app_board_screen.dart`、`unified_waterfall_screen.dart` | 看板/瀑布流视图。 |
| `screen_time_detail_screen.dart` | 屏幕时间详情分析。 |
| `settings_screen.dart`、`home_settings_screen.dart`、`animation_settings_page.dart` | 设置入口和偏好设置。 |
| `about_screen.dart`、`feature_guide_screen.dart`、`ai_assistant_tutorial_screen.dart` | 关于、功能引导和 AI 教程。 |
| `band_sync_screen.dart` | 手环同步配置。 |
| `quiz_screen.dart`、`math_menu_screen.dart`、`other_screens.dart` | 数学测验和次级页面。 |

## 子目录

- `pomodoro/`：番茄钟工作台、统计视图和专用组件。
- `settings/`：设置页面、设置区块、弹窗和事件处理。

## 当前交互说明

- `todo_plan_screen.dart` 区分点击创建和滑动创建规划块：点击创建时选择待办会启用 AI 时长估计；滑动创建时保留用户选出的时间段，不自动覆盖时间。
- `home_dashboard.dart` 接收 WebSocket `SYNC_DATA` 信号，并通过防抖触发静默同步和刷新。
- 平台特定 UI 必须保持显式守卫，Windows 灵动岛/悬浮窗逻辑不能在 Android 运行。
