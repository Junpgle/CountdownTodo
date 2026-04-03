# screens/ — 页面层（表现层）

## 目录定位

表现层（Presentation Layer），包含所有全屏页面组件，负责用户交互与数据展示。

---

## 文件索引

| 文件 | 页面 | 核心功能 |
|------|------|----------|
| `home_dashboard.dart` | 主仪表盘 | 首页聚合：待办、倒计时、课表、屏幕时间、番茄钟 |
| `login_screen.dart` | 登录/注册 | 邮箱验证码登录、双栏布局、自适应深色模式 |
| `quiz_screen.dart` | 数学测验 | 10题测验、会话暂存、答题进度恢复 |
| `pomodoro_screen.dart` | 番茄钟 | 专注计时、标签管理、跨端感知 |
| `add_todo_screen.dart` | 添加待办 | 手动创建 / LLM 智能解析 |
| `todo_confirm_screen.dart` | 待办确认 | 图片识别结果确认页 |
| `settings_screen.dart` | 设置入口 | 设置分类导航 |
| `about_screen.dart` | 关于页面 | 版本信息、更新日志 |
| `screen_time_detail_screen.dart` | 屏幕时间详情 | 7日趋势图、分类统计 |
| `time_log_screen.dart` | 时间日志 | 手动记录时间块 |
| `historical_countdowns_screen.dart` | 历史倒计时 | 已删除倒计时回收站 |
| `historical_todos_screen.dart` | 历史待办 | 已完成/已删除待办 |
| `feature_guide_screen.dart` | 功能引导 | 首次安装引导页 |
| `other_screens.dart` | 其他页面 | 排行榜、测验设置等 |
| `course_screens.dart` | 课程相关 | 课表导入、解析 |
| `math_menu_screen.dart` | 数学菜单 | 测验入口、历史记录 |
| `home_settings_screen.dart` | 首页设置 | 板块显隐、排列顺序 |

### 子目录

#### `pomodoro/` — 番茄钟子模块

```
pomodoro/
├── pomodoro_utils.dart     # 番茄钟工具函数
├── views/                  # 番茄钟视图页面
└── widgets/                # 番茄钟专用组件
```

#### `settings/` — 设置子模块

```
settings/
├── dialogs/                # 设置弹窗
├── handlers/               # 设置事件处理
├── widgets/                # 设置专用组件
├── llm_config_page.dart    # LLM 配置页
└── server_choice_page.dart # 服务器选择页
```

---

## 核心逻辑摘要

### home_dashboard.dart (1992行)

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

### login_screen.dart (1032行)

- 自适应颜色系统：`_T` 类封装深色/浅色两套色值
- 双栏布局：左侧面板展示特性，右侧表单
- 支持邮箱验证码注册流

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
