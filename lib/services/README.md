# services/ — 服务层（业务层 / 领域层）

## 目录定位

业务层（Business Layer），封装全部领域服务与外部接口适配，是 UI 层与数据层之间的桥梁。

---

## 文件索引

### 核心服务

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `api_service.dart` | HTTP API 客户端，封装所有后端请求 | `ApiService` (静态类) |
| `pomodoro_service.dart` | 番茄钟核心：数据模型、状态管理、云端同步 | `PomodoroService`, `PomodoroTag`, `PomodoroRecord`, `PomodoroRunState` |
| `notification_service.dart` | 本地通知：课程、待办、番茄钟、图片识别进度 | `NotificationService` |
| `llm_service.dart` | 大模型智能解析：文本/图片 → 待办 JSON | `LLMService`, `LLMConfig` |

### 平台适配

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `screen_time_service.dart` | 屏幕时间采集：Android UsageStats / Windows TAI | `ScreenTimeService` |
| `tai_service.dart` | Windows 进程活跃时间采集 (Tai API) | `TaiService` |
| `float_window_service.dart` | 桌面悬浮窗初始化 | `FloatWindowService` |
| `window_service.dart` | 窗口生命周期管理 | `WindowService` |
| `widget_service.dart` | Android 桌面小组件 | `WidgetService` |
| `system_control_service.dart` | 系统控制：亮度、音量等 | `SystemControlService` |

### 课表解析器

| 文件 | 适配院校/系统 | 关键导出 |
|------|--------------|----------|
| `course_service.dart` | 课表统一管理入口 | `CourseService`, `CourseItem` |
| `hfut_schedule_parser.dart` | 合肥工业大学 (JSON 格式) | `HfutScheduleParser` |
| `xmu_schedule_parser.dart` | 厦门大学 (HTML/正方教务) | `XmuScheduleParser` |
| `xidian_schedule_parser.dart` | 西安电子科技大学 (ICS 格式) | `XidianScheduleParser` |
| `zfsoft_schedule_parser.dart` | 正方教务系统通用解析 | `ZfsoftScheduleParser` |

### 同步 & 数据

| 文件 | 职责 |
|------|------|
| `pomodoro_sync_service.dart` | 番茄钟跨端 WebSocket 同步 |
| `migration_service.dart` | 数据迁移 |
| `chat_storage_service.dart` | 聊天消息本地存储 |
| `island_data_provider.dart` | 灵动岛数据源 |
| `island_slot_provider.dart` | 灵动岛插槽管理 |

### 业务服务

| 文件 | 职责 |
|------|------|
| `reminder_schedule_service.dart` | 定时提醒调度 |
| `snooze_dialog.dart` | 稍后提醒弹窗 |
| `todo_parser_service.dart` | 待办解析（LLM 调用封装） |
| `external_share_handler.dart` | 接收外部分享内容 → LLM 解析 |
| `clipboard_service.dart` | 剪贴板读写 |
| `band_sync_service.dart` | 手环同步服务 |
| `splash_service.dart` | 启动页服务 |
| `animation_config_service.dart` | 动画配置服务 |

---

## 核心逻辑摘要

### api_service.dart

统一 HTTP 客户端，核心职责：

1. **双服务器切换**：Cloudflare (`mathquiz.junpgle.me`) / 阿里云 (`101.200.13.100:8082`)
2. **SSL 绕过**：`IOClient` + `badCertificateCallback` 全局跳过证书校验
3. **Token 管理**：`_authToken` 内存持有，`_getHeaders()` 自动注入 `Bearer` 头

**关键 API 端点：**

```dart
// 认证
ApiService.register(username, email, password)
ApiService.login(email, password)

// 增量同步 (核心)
ApiService.postDeltaSync(
  userId, lastSyncTime, deviceId,
  todosChanges, countdownsChanges,
  screenTime, timeLogsChanges,
)

// 屏幕时间
ApiService.uploadScreenTime(userId, deviceName, date, apps)
ApiService.fetchScreenTime(userId, date)

// 番茄钟
ApiService.syncPomodoroTags(tags)
ApiService.uploadPomodoroRecord(record)
ApiService.fetchPomodoroRecords(userId, fromMs, toMs)
```

### pomodoro_service.dart

番茄钟领域模型 + 服务一体化：

```
PomodoroTag           ← 标签（支持 Delta Sync）
  ├── uuid, name, color
  └── isDeleted, version, updatedAt

PomodoroRecord        ← 专注记录
  ├── uuid, todoUuid, tagUuids
  ├── startTime, endTime, plannedDuration
  ├── status: completed | interrupted | switched
  └── effectiveDuration (getter)

PomodoroSettings      ← 用户配置
  ├── focusMinutes, breakMinutes, cycles
  └── mode: countdown | countUp

PomodoroRunState      ← 运行时状态（防误杀持久化）
  ├── phase: idle | focusing | breaking | finished
  ├── sessionUuid, targetEndMs
  └── todoUuid, tagUuids
```

**Stream 响应机制：**
```dart
// UI 层通过 Stream 监听状态变更，替代轮询
PomodoroService.onRunStateChanged.listen((state) { ... });
```

**标签墓碑机制：**
```dart
// 删除标签时打 isDeleted=true 的墓碑，防止云端同步复活
await PomodoroService.deleteTag(uuid);
```

### llm_service.dart

大模型调用封装，支持：
1. **文本解析**：自然语言 → 待办 JSON（`parseTodoWithLLM`）
2. **图片解析**：截图 → 待办 JSON（`parseTodoFromImage`）
3. **取餐码识别**：优先检测 KFC/顺丰/茶百道等品牌 + 取餐码

**Prompt 工程要点：**
- 基准时间注入：`{now}` 替换为当前时间
- 取餐码场景优先级最高
- 输出必须是纯 JSON 数组，禁止 Markdown 包裹

### course_service.dart

课表统一管理：
- 支持 4 种导入格式：HFUT JSON / XMU HTML / XD ICS / ZFSoft HTML
- `CourseItem` 统一数据模型，序列化到 SharedPreferences
- 解析器职责单一：只负责格式转换，不涉及存储

---

## 调用链路

```
screens/ (UI层)
  ├── ApiService               ← 登录、同步、数据拉取
  ├── PomodoroService          ← 番茄钟 CRUD、统计
  ├── LLMService               ← 智能解析待办
  ├── ScreenTimeService        ← 屏幕时间采集
  ├── CourseService            ← 课表导入/查询
  └── NotificationService      ← 通知推送

services/ 内部依赖
  ├── api_service.dart         ← 被所有需要网络的服务依赖
  ├── storage_service.dart     ← 被 pomodoro_service, course_service 等依赖
  └── tai_service.dart         ← 被 screen_time_service 依赖 (Windows)
```

---

## 外部依赖

- `http` / `io_client`：HTTP 请求
- `web_socket_channel`：WebSocket 连接（番茄钟跨端同步）
- `flutter_local_notifications`：本地通知
- `shared_preferences`：本地缓存
- `html`：HTML 解析（课表导入）
- `sqflite_common_ffi`：桌面端 SQLite 读取

---

*最后更新：2026-04-05*
