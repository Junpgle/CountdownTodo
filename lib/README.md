# lib/ — Flutter 主工程源码

## 目录定位

应用层（Application Layer），承载全部 Dart 业务代码，是整个 Flutter 项目的根目录。

---

## 核心文件

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `main.dart` | 应用入口、路由注册、主题管理、插件初始化、灵动岛分流 | `MyApp`, `appNavigatorKey`, `showCloseDialog()` |
| `models.dart` | 领域模型定义 | `Question`, `TodoItem`, `CountdownItem`, `TimeLogItem`, `RecurrenceType` |
| `storage_service.dart` | 本地持久化 & 增量同步引擎 & 用户系统 | `StorageService` (静态类) |
| `update_service.dart` | 版本检查、下载、安装 | `UpdateService`, `AppManifest` |

---

## 子目录

| 目录 | 文件数 | 职责 |
|------|--------|------|
| `screens/` | 27 页面文件 | 全屏页面组件（表现层） |
| `services/` | 28 服务文件 | 业务逻辑 & 外部接口适配 |
| `widgets/` | 6 组件文件 | 可复用 UI 组件 |
| `windows_island/` | 12 文件 | Windows 桌面灵动岛模块 |
| `models/` | 1 文件 | 扩展数据模型 |
| `utils/` | 1 文件 | 工具函数 |

---

## 核心逻辑摘要

### main.dart

- 检测 `multi_window` 参数，分流到 `islandMain`（灵动岛独立窗口）
- 初始化 `WindowService`、主题、登录状态
- 根据登录状态路由到 `LoginScreen` 或 `HomeDashboard`
- 注册全局关闭确认对话框回调

### models.dart

**数据模型架构：**

```
Question              ← 数学测验题目
  ├── num1, num2, operatorSymbol
  └── checkAnswer()

TodoItem              ← 待办事项（支持 Delta Sync）
  ├── id (UUID), version, updatedAt
  ├── recurrence (RecurrenceType enum)
  └── markAsChanged()  // 每次修改必须调用

CountdownItem         ← 倒计时（支持 Delta Sync）
  ├── id (UUID), targetDate, version
  └── markAsChanged()

TimeLogItem           ← 时间日志
  ├── id, title, tagUuids, startTime, endTime
  └── markAsChanged()
```

**时间规范：** 所有时间字段统一使用 UTC 毫秒时间戳 (`int`)，显示时转本地时区。

### storage_service.dart

核心职责：
1. **用户系统**：注册、登录、会话管理
2. **增量同步**：`syncData()` 实现 LWW (Last Write Wins) 策略，支持 Todos/Countdowns/TimeLogs
3. **屏幕时间**：本地缓存 + 14天滑动窗口 + 云端聚合
4. **番茄钟标签**：持久化与云端同步
5. **设备标识**：每账号独立 UUID，防止多端冲突

**同步水位线机制：**
```dart
// last_sync_time_$username 记录上次同步时间点
// 仅上传 updatedAt > lastSyncTime 的脏数据
```

---

## 调用链路

```
main.dart
  ├── StorageService          ← 读取登录状态、主题偏好
  ├── ApiService              ← 设置服务器、Token
  ├── FloatWindowService      ← 桌面端灵动岛初始化
  └── IslandManager           ← 创建独立窗口

screens/ (页面层)
  └── 依赖 models.dart, storage_service.dart, services/*

services/ (服务层)
  └── 依赖 models.dart, storage_service.dart, api_service.dart
```

---

## 依赖关系

**对外部插件依赖：**
- `shared_preferences`：本地键值存储
- `http` / `io_client`：网络请求
- `uuid`：生成全局唯一 ID
- `intl`：时间格式化
- `device_info_plus`：设备型号识别
- `window_manager` / `desktop_multi_window`：桌面窗口管理
- `flutter_local_notifications`：本地通知

---

*最后更新：2026-04-05*
