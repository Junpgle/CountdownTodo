# widgets/ — 可复用 UI 组件层

最后更新：`2026-05-24`

## 目录定位

`widgets/` 保存跨页面复用的展示组件和首页功能板块。大型、只属于单一页面的流程应保留在 `screens/`。

## 主要组件

| 文件 | 职责 |
|------|------|
| `home_app_bar.dart` | 首页顶部栏、同步入口、账号/设置入口。 |
| `home_sections.dart` | 首页通用卡片和标题，如屏幕时间、学期进度。 |
| `todo_section_widget.dart` | 首页待办区块和快捷操作。 |
| `todo_group_widget.dart` | 待办分组/文件夹展示。 |
| `countdown_section_widget.dart` | 首页倒数日区块。 |
| `course_section_widget.dart` | 首页课程区块，以及规划/课程显示辅助。 |
| `pomodoro_today_section.dart` | 今日番茄钟摘要。 |
| `plan_block_today_section.dart` | 今日规划块摘要。 |
| `personal_timeline_section.dart` | 个人时间线首页区块。 |
| `medal_recommendation_card.dart` | 勋章推荐卡片和弹窗。 |
| `global_search_overlay.dart` | 全局搜索浮层。 |
| `sync_status_banner.dart` | 同步状态展示。 |
| `conflict_alert_dialog.dart` | 冲突提醒弹窗。 |
| `privacy_policy_dialog.dart` | 隐私政策弹窗。 |
| `sticky_announcement_banner.dart` | 团队公告置顶横幅。 |
| `team_gantt_widget.dart` / `team_heatmap_widget.dart` | 团队可视化组件。 |
| `ai_water_border.dart` | AI 视觉边框效果。 |

## 使用规则

- 首页区块应接收 `HomeDashboard` 或服务层传入的数据，不要在组件里承担大范围同步编排。
- 触发平台能力的组件应通过 service 层调用，并把平台守卫放在 service 或 screen 层。
- 单屏专用布局不要随意放入这里，除非已经被多个页面复用。
