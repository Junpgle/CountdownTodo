# CountDownTodo — 跨平台效率工具套件

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.1+-blue)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Web-green)]()
[![Version](https://img.shields.io/badge/Version-3.2.14-orange)]()

CountDownTodo 是一款跨平台的生产力与时间管理套件，集成待办事项、倒计时、番茄钟、数学测验、课程表、屏幕时间统计等功能，支持 Android / Windows / Web 多端数据同步。

> **注意**：C++ 桌面悬浮组件 (`MathQuizLite/`) 位于独立仓库 [CountDownTodoLite](https://github.com/Junpgle/CountDownTodoLite)，本仓库仅包含 Flutter 移动端 + Cloudflare Workers 后端。

---

## 🏗️ 技术架构

| 层级 | 技术栈 | 职责 |
|------|--------|------|
| **表现层** | Flutter Widgets + Material3 | UI 渲染、主题切换、响应式布局 |
| **业务层** | Dart Services | 番茄钟状态机、增量同步引擎、LLM 解析 |
| **持久层** | SharedPreferences + REST API | 本地缓存 + Cloudflare Workers 后端 |
| **原生层** | MethodChannel + Win32 FFI | 屏幕时间采集、桌面灵动岛、通知推送 |

---

## 📂 项目结构

```
math_quiz_app/
├── lib/                          # Flutter 主工程 (107 文件)
│   ├── main.dart                 # 应用入口 & 路由
│   ├── models.dart               # 核心数据模型
│   ├── models/                   # 扩展数据模型
│   │   └── chat_message.dart     # 聊天消息模型
│   ├── storage_service.dart      # 本地存储 & 增量同步引擎
│   ├── update_service.dart       # 版本更新 & 下载管理
│   ├── utils/                    # 工具函数
│   │   └── page_transitions.dart # 页面转场动画
│   ├── screens/                  # 页面层 (27 页面文件)
│   │   ├── home_dashboard.dart   # 主仪表盘
│   │   ├── login_screen.dart     # 登录/注册
│   │   ├── splash_screen.dart    # 启动页
│   │   ├── quiz_screen.dart      # 数学测验
│   │   ├── pomodoro_screen.dart  # 番茄钟
│   │   ├── todo_chat_screen.dart # 待办聊天
│   │   ├── todo_confirm_screen.dart # 待办确认
│   │   ├── time_log_screen.dart  # 时间日志
│   │   ├── screen_time_detail_screen.dart # 屏幕时间详情
│   │   ├── historical_todos_screen.dart   # 历史待办
│   │   ├── historical_countdowns_screen.dart # 历史倒计时
│   │   ├── course_screens.dart   # 课程管理
│   │   ├── band_sync_screen.dart # 手环同步
│   │   ├── feature_guide_screen.dart # 功能引导
│   │   ├── settings_screen.dart  # 设置入口
│   │   ├── about_screen.dart     # 关于页面
│   │   ├── pomodoro/             # 番茄钟子模块 (7 文件)
│   │   └── settings/             # 设置子模块 (14 文件)
│   ├── services/                 # 服务层 (28 服务文件)
│   │   ├── api_service.dart      # HTTP API 客户端
│   │   ├── pomodoro_service.dart # 番茄钟核心逻辑
│   │   ├── llm_service.dart      # 大模型智能解析
│   │   ├── course_service.dart   # 课表解析 & 管理
│   │   ├── screen_time_service.dart # 屏幕时间采集
│   │   ├── notification_service.dart # 通知服务
│   │   ├── band_sync_service.dart # 手环同步
│   │   ├── tai_service.dart      # Windows TAI 采集
│   │   ├── migration_service.dart # 数据迁移
│   │   ├── reminder_schedule_service.dart # 提醒调度
│   │   └── *_schedule_parser.dart # 4 校课表解析器
│   ├── widgets/                  # 可复用 UI 组件 (6 文件)
│   └── windows_island/           # Windows 灵动岛模块 (12 文件)
├── math-quiz-backend/            # Cloudflare Workers 后端
│   ├── src/index.js              # API 路由
│   └── wrangler.toml             # CF 部署配置
├── CountDownTodo-band/           # 手环同步模块
├── interconnect_dev_test_demo/   # 互联测试演示
├── android/                      # Android 原生代码
├── windows/                      # Windows 平台配置
├── web/                          # Web 平台配置
└── assets/                       # 静态资源
```

---

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.1.0
- Dart SDK >= 3.1.0
- Android Studio / VS Code

### 运行

```bash
# 安装依赖
flutter pub get

# 运行 Android
flutter run

# 运行 Windows
flutter run -d windows

# 运行 Web
flutter run -d chrome
```

### 后端部署

```bash
cd math-quiz-backend
npm install
npx wrangler deploy
```

---

## 📖 文档索引

- [项目架构](docs/PROJECT_ARCHITECTURE.md)
- [灵动岛重新设计计划](docs/ISLAND_REDESIGN_PLAN.md)
- [lib/ 源码总览](lib/README.md)
- [screens/ 页面层](lib/screens/README.md)
- [services/ 服务层](lib/services/README.md)
- [widgets/ 组件层](lib/widgets/README.md)
- [windows_island/ 灵动岛](lib/windows_island/README.md)
- [windows_island/ 扩展指南](lib/windows_island/EXTENDING.md)

---

*最后更新：2026-04-05*
*版本：v3.0.8*
