# widgets/ — 可复用 UI 组件层

## 目录定位

表现层的公共组件库，抽取首页各功能板块为独立 Widget，供 `HomeDashboard` 组合使用。

---

## 文件索引

| 文件 | 组件 | 职责 |
|------|------|------|
| `home_app_bar.dart` | `HomeAppBar` | 首页顶部栏：问候语、用户头像、同步按钮、设置入口 |
| `home_sections.dart` | `SectionHeader`, `ScreenTimeCard`, `SemesterProgressCard` | 通用板块标题、屏幕时间卡片、学期进度条 |
| `todo_section_widget.dart` | `TodoSectionWidget` | 待办事项板块：今日待办列表、勾选完成、快速添加 |
| `countdown_section_widget.dart` | `CountdownSectionWidget` | 倒计时板块：重要日期卡片、剩余天数 |
| `course_section_widget.dart` | `CourseSectionWidget` | 课程提醒板块：今日课程、下一节课高亮 |
| `pomodoro_today_section.dart` | `PomodoroTodaySection` | 今日番茄钟统计：专注时长、标签分布 |

---

## 核心逻辑摘要

### home_sections.dart

通用基础组件：

**SectionHeader** — 板块标题栏
```dart
SectionHeader(
  title: '待办事项',
  icon: Icons.check_circle,
  onAdd: () => _showAddTodo(),  // 可选的添加按钮
  isLight: false,               // 浅色模式适配
)
```

**ScreenTimeCard** — 屏幕时间卡片
- 响应式布局：`LayoutBuilder` 检测 `>=600px` 为平板
- 三种状态：无权限 → 引导开启、加载中 → 骨架屏、有数据 → 条形图
- 点击跳转 `ScreenTimeDetailScreen`

**SemesterProgressCard** — 学期进度条
- 从 `StorageService` 读取学期起止日期
- 线性进度条 + 百分比文字

### todo_section_widget.dart

待办板块核心逻辑：

1. **今日筛选**：`dueDate` 为今天的全天待办
2. **自动重置**：每日首次加载时重置已完成的重复待办
3. **勾选动画**：`AnimatedContainer` 平滑过渡
4. **通知联动**：勾选后调用 `NotificationService.updateTodoNotification` 刷新通知

**关键状态：**
```dart
class TodoSectionWidgetState extends State<TodoSectionWidget> {
  List<TodoItem> _todayTodos;
  bool _isLoading;
  
  Future<void> _toggleTodo(TodoItem todo) async { ... }
  Future<void> _loadTodos() async { ... }
}
```

### countdown_section_widget.dart

倒计时板块：
- 按 `targetDate` 升序排列，最近的在前
- 过期倒计时显示灰色
- 长按可编辑/删除

### course_section_widget.dart

课程提醒板块：
- 从 `CourseService` 加载今日课程
- 高亮"当前正在进行"的课程
- 下一节课单独展示

### pomodoro_today_section.dart

今日番茄钟统计：
- 从 `PomodoroService.getTodayRecords()` 获取今日记录
- 计算总专注时长（`totalFocusSeconds`）
- 按标签分布展示（`focusByTag`）

---

## 调用链路

```
HomeDashboard (父容器)
  ├── HomeAppBar              ← 顶部栏
  ├── CourseSectionWidget     ← 依赖 CourseService
  ├── TodoSectionWidget       ← 依赖 StorageService, NotificationService
  ├── CountdownSectionWidget  ← 依赖 StorageService
  ├── ScreenTimeCard          ← 依赖 ScreenTimeService (传入 stats)
  └── PomodoroTodaySection    ← 依赖 PomodoroService

home_sections.dart (基础组件)
  └── 被上述所有 Section Widget 引用
```

---

## 外部依赖

- `cached_network_image`：头像/壁纸加载
- `intl`：时间格式化
- `flutter/material.dart`：Material3 组件

---

*最后更新：2026-04-05*
