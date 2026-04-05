# screens/ — 页面层（表现层）

## 目录定位

表现层（Presentation Layer），包含所有全屏页面组件，负责用户交互与数据展示。

---

## 文件索引

### 主要页面

| 文件 | 页面 | 核心功能 |
|------|------|----------|
| `splash_screen.dart` | 启动页 | 应用启动画面、初始化检查 |
| `home_dashboard.dart` | 主仪表盘 | 首页聚合：待办、倒计时、课表、屏幕时间、番茄钟 |
| `login_screen.dart` | 登录/注册 | 邮箱验证码登录、双栏布局、自适应深色模式、数据迁移 |
| `quiz_screen.dart` | 数学测验 | 10题测验、会话暂存、答题进度恢复 |
| `pomodoro_screen.dart` | 番茄钟 | 专注计时、标签管理、跨端感知 |
| `add_todo_screen.dart` | 添加待办 | 手动创建 / LLM 智能解析 |
| `todo_confirm_screen.dart` | 待办确认 | 图片识别结果确认页 |
| `todo_chat_screen.dart` | 待办聊天 | 待办相关聊天交互 |
| `settings_screen.dart` | 设置入口 | 设置分类导航 |
| `about_screen.dart` | 关于页面 | 版本信息、更新日志 |
| `screen_time_detail_screen.dart` | 屏幕时间详情 | 7日趋势图、分类统计 |
| `time_log_screen.dart` | 时间日志 | 手动记录时间块 |
| `time_log_components.dart` | 时间日志组件 | 时间日志页面专用组件 |
| `historical_countdowns_screen.dart` | 历史倒计时 | 已删除倒计时回收站 |
| `historical_todos_screen.dart` | 历史待办 | 已完成/已删除待办 |
| `feature_guide_screen.dart` | 功能引导 | 首次安装引导页 |
| `other_screens.dart` | 其他页面 | 排行榜、测验设置等 |
| `course_screens.dart` | 课程相关 | 课表导入、解析 |
| `math_menu_screen.dart` | 数学菜单 | 测验入口、历史记录 |
| `home_settings_screen.dart` | 首页设置 | 板块显隐、排列顺序 |
| `band_sync_screen.dart` | 手环同步 | 手环数据同步配置 |
| `animation_settings_page.dart` | 动画设置 | 动画效果配置 |

### 子目录

#### `pomodoro/` — 番茄钟子模块

```
pomodoro/
├── pomodoro_utils.dart         # 番茄钟工具函数
├── views/                      # 番茄钟视图页面
│   ├── workbench_view.dart     # 工作台视图
│   └── stats_view.dart         # 统计视图
└── widgets/                    # 番茄钟专用组件
    ├── workbench_task_area.dart    # 任务区域
    ├── workbench_actions.dart      # 操作按钮
    ├── tag_manager_sheet.dart      # 标签管理面板
    ├── immersive_timer.dart        # 沉浸式计时器
    └── fading_indexed_stack.dart   # 淡入淡出 IndexedStack
```

#### `settings/` — 设置子模块

```
settings/
├── widgets/                    # 设置专用组件 (8 文件)
│   ├── account_section.dart    # 账户设置区块
│   ├── about_section.dart      # 关于区块
│   ├── advanced_section.dart   # 高级设置区块
│   ├── course_section.dart     # 课表设置区块
│   ├── permission_section.dart # 权限设置区块
│   ├── preference_section.dart # 偏好设置区块
│   ├── semester_section.dart   # 学期设置区块
│   └── system_section.dart     # 系统设置区块
├── handlers/                   # 设置事件处理 (3 文件)
│   ├── course_import_handler.dart    # 课表导入处理
│   ├── permission_handler.dart       # 权限处理
│   └── storage_management_handler.dart # 存储管理处理
├── dialogs/                    # 设置弹窗 (6 文件)
│   ├── change_password_dialog.dart   # 修改密码
│   ├── home_section_manager_dialog.dart # 首页板块管理
│   ├── island_priority_dialog.dart   # 灵动岛优先级
│   ├── llm_config_dialog.dart        # LLM 配置
│   ├── migration_dialog.dart         # 数据迁移
│   └── zf_time_config_dialog.dart    # 正方教务时间配置
├── server_choice_page.dart     # 服务器选择页
├── notification_settings_page.dart # 通知设置页
├── llm_config_page.dart        # LLM 配置页
└── device_version_detail_page.dart # 设备版本详情
```

---

## 核心逻辑摘要

### home_dashboard.dart

首页是应用的核心枢纽，职责包括：

1. **数据聚合加载**：倒计时、待办、课表、屏幕时间、番茄钟记录
2. **定时刷新**：
   - 每分钟检查即将开始的课程/待办
   - 每2分钟同步屏幕时间
   - 启动时静默检查更新
3. **跨端番茄钟感知**：通过 `PomodoroSyncService` WebSocket 监听其他设备的专注状态
4. **本地番茄钟监测**：通过 `PomodoroService.onRunStateChanged` Stream 响应状态变更
5. **外部分享处理**：`ExternalShareHandler` 接收分享内容 → LLM 解析 → 待办确认

**关键状态变量：**
```dart
List<CountdownItem> _countdowns;      // 倒计时列表
List<TodoItem> _todos;                // 待办列表
List<dynamic> _screenTimeStats;       // 屏幕时间
CrossDevicePomodoroState? _remotePomodoro;  // 跨端专注状态
PomodoroRunState? _localPomodoro;     // 本地专注状态
```

### login_screen.dart

- 自适应颜色系统：`_T` 类封装深色/浅色两套色值
- 双栏布局：左侧面板展示特性，右侧表单
- 支持邮箱验证码注册流
- 包含遗留数据迁移逻辑

### quiz_screen.dart

- **会话暂存**：`static QuizSession? _currentSession` 在页面销毁后保留状态
- **答题进度恢复**：重新进入页面可继续上次进度
- **通知联动**：每题切换更新系统通知

---

## 调用链路

```
main.dart
  └── HomeDashboard (登录后)    ← 依赖 services/*, widgets/*
  └── LoginScreen (未登录)      ← 依赖 ApiService, StorageService

HomeDashboard
  ├── TodoSectionWidget         ← 待办板块
  ├── CountdownSectionWidget    ← 倒计时板块
  ├── CourseSectionWidget       ← 课表板块
  ├── PomodoroTodaySection      ← 番茄钟板块
  └── ScreenTimeCard            ← 屏幕时间卡片 (在 home_sections.dart)
```

---

## 外部依赖

- `cached_network_image`：壁纸/头像缓存
- `permission_handler`：权限申请
- `package_info_plus`：版本信息
- `file_picker`：文件选择（课表导入）
- `receive_sharing_intent`：接收外部分享

---

*最后更新：2026-04-05*
