# lib/ — Flutter 主工程源码

最后更新：`2026-05-24`

## 目录定位

`lib/` 是主 Flutter 应用代码目录，包含 UI、领域模型、本地存储、同步编排、AI action、课程导入、平台集成和 Windows 灵动岛逻辑。

## 核心文件

| 文件 | 职责 |
|------|------|
| `main.dart` | 应用入口、插件初始化、登录路由、手环同步桥接、Windows 灵动岛进程分流。 |
| `models.dart` | 核心模型：待办、倒数日、时间日志、课程、规划块、冲突、题目。 |
| `storage_service.dart` | SQLite 主存储、oplog 收集、增量同步、屏幕时间缓存、冲突处理。 |
| `update_service.dart` | 更新清单读取、更新提示、安装包下载和安装流程。 |

## 子目录

| 目录 | 当前职责 |
|------|----------|
| `course_import/` | 课程导入处理器、解析器、WebView 导入 UI 和时间配置。 |
| `models/` | AI action、聊天消息、勋章 ML 等扩展模型。 |
| `screens/` | 全屏页面和功能页面。 |
| `services/` | API、同步、数据库、番茄钟、AI、课程、时间线、通知、平台服务。 |
| `utils/` | 导航、时区、动效、页面转场等工具。 |
| `widgets/` | 可复用 UI 组件和首页功能板块。 |
| `windows_island/` | Windows-only 灵动岛/悬浮窗实现。 |

## 存储模型

- SQLite 是高容量业务数据的主存储。
- `SharedPreferences` 保留设置、登录态、同步水位线、小缓存和旧数据迁移兼容。
- `op_logs` 用于记录待上传变更。
- 待办、倒数日、番茄钟等大体量 JSON 镜像不再写回 `SharedPreferences`，避免 Android 插件层 OOM。

## 主要数据族

- `TodoItem`、`TodoGroup`、`CountdownItem`、`TimeLogItem`。
- `TodoPlanBlock`：绑定已有待办的具体计划时间块。
- `PomodoroRecord`、`PomodoroTag`：定义在 `services/pomodoro_service.dart`。
- `CourseItem` 和课程导入相关模型。
- `models/` 下的 AI action、聊天消息和勋章 ML 模型。

## 调用链路

```text
main.dart
  ├── StorageService           登录状态、设置、同步
  ├── ApiService               后端选择、Token、HTTP 调用
  ├── PomodoroSyncService      WebSocket 跨端感知
  ├── BandSyncService          手环数据桥接
  ├── WindowService            桌面生命周期
  └── islandMain               Windows 灵动岛进程分支

screens/
  ├── services/*               业务逻辑和平台能力
  ├── storage_service.dart      应用数据和同步
  └── widgets/*                可复用展示组件
```

## 平台边界

Windows 灵动岛和 floating-window 服务必须保持 Windows-only。Android 代码不得导入、执行或初始化这些 Windows-only 逻辑。
