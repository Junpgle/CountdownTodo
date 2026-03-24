# CountDownTodo 项目架构文档

> **文档版本**: v2.1.6
> **最后更新**: 2026-03-17
> **适用范围**: Flutter 移动端 + Cloudflare Workers 后端
> **目标读者**: AI 助手、新加入的开发者、代码审查人员

---

## 版本来源（基于 Git）
- 当前分支: `master`
- 最近提交: `d0796fd` (2026-03-17) — 提交信息: "v2.1.6 拆分番茄钟"
- Git describe 输出: `v1.5.6-158-gd0796fd-dirty`  （表示基于 tag `v1.5.6` 后 158 次提交，当前工作区有改动）

> 说明：文档版本以当前构建/发布线（git commit 所指）为准；如果需要同步 `pubspec.yaml` 中的应用版本，请在发布前手动更新 `pubspec.yaml` 的 `version` 字段。

---

## 📋 目录

1. [项目概览](#项目概览)
2. [技术栈清单](#技术栈清单)
3. [目录结构详解](#目录结构详解)
4. [核心架构设计](#核心架构设计)
5. [开发规范](#开发规范)
6. [常见开发场景](#常见开发场景)
7. [已知技术债与注意事项](#已知技术债与注意事项)
8. [调试与部署](#调试与部署)

---

## 项目概览

### 项目定位
CountDownTodo 是一个**跨平台生产力与时间管理工具**，核心功能包括：
- ✅ **待办事项管理**：支持每日/自定义周期重复，全天/时段事件，备注字段
- ⏰ **重要日倒计时**：纪念日提醒与可视化倒计时
- 📚 **智能课程表**：支持合工大/厦大/西电等教务系统导入，ICS 文件解析
- 📊 **多端屏幕时长统计**：Android + Windows (Tai) 数据融合，分类统计
- 🧮 **数学练习系统**：自定义难度的口算训练 + 全球与本地排行榜
- 🍅 **番茄钟专注系统**：任务绑定、标签管理、多维度统计、时间全览 (周/日视图)、跨端实时状态同步 (WebSocket)

### 技术特色
1. **增量同步算法 (Delta Sync)**：仅传输变更数据，支持离线编辑
2. **逻辑删除机制**：软删除设计，支持回收站与跨设备同步
3. **LWW 冲突解决**：Last Write Wins 策略，基于版本号 + 时间戳
4. **Serverless 架构**：零运维成本的云端后端

### 代码仓库
- **移动端 + 后端**: 当前仓库
- **桌面端 (C++)**: [CountDownTodoLite](https://github.com/Junpgle/CountDownTodoLite)

---

## 技术栈清单

### 🎯 移动端 (Flutter)

| 分类 | 技术/库 | 版本 | 用途 |
|------|--------|------|------|
| **框架** | Flutter SDK | ≥3.0.0 | 跨平台 UI 框架 |
| **语言** | Dart | ≥3.0.0 | 业务逻辑语言 |
| **UI 系统** | Material Design 3 | - | 视觉设计规范 |
| **状态管理** | StatefulWidget + ValueNotifier | - | 轻量级原生方案 |
| **本地存储** | SharedPreferences | ^2.2.0 | 键值对持久化 |
| **网络请求** | http | ^1.2.0 | REST API 调用 |
| **国际化** | intl | ^0.20.2 | 日期格式化 + 中英文 |
| **唯一标识** | uuid | ^4.2.2 | 生成全局唯一 ID |
| **桌面小部件** | home_widget | ^0.9.0 | Android 桌面组件 |
| **本地通知** | flutter_local_notifications | ^20.0.0 | 推送提醒 |
| **权限管理** | permission_handler | ^12.0.1 | Android/iOS 权限 |
| **下载管理** | flutter_downloader | ^1.12.0 | 应用更新下载 |
| **图片缓存** | cached_network_image | ^3.3.0 | 网络图片优化 |
| **窗口管理** | window_manager | ^0.3.8 | 桌面端窗口控制 |
| **实时通信** | web_socket_channel | ^3.0.1 | 番茄钟跨端 WebSocket 同步 |
| **桌面数据库读取**| sqflite_common_ffi | ^2.3.0 | 读取 Windows Tai 库数据 |
| **意图分享** | receive_sharing_intent | ^1.8.1 | 处理外部文本与文件分享 |

### 🌐 后端 (Serverless & WebSocket)

| 分类 | 技术/库 | 用途 |
|------|--------|------|
| **运行时** | Cloudflare Workers | Serverless 计算平台 |
| **数据库** | Cloudflare D1 (SQLite) | 关系型数据库 |
| **认证** | JWT + Bearer Token | 用户身份验证 |
| **邮件服务** | Resend API | 邮箱验证码发送 |
| **构建工具** | Wrangler ^3.101.0 | Workers 部署工具 |
| **测试框架** | Vitest ^3.2.0 | 单元测试 |

### 📱 Android 原生

| 分类 | 技术 | 版本 |
|------|------|------|
| **编译 SDK** | Android 15 | SDK 36 |
| **最低支持** | Android 8.0 | SDK 26 |
| **编程语言** | Kotlin + Java | JVM 17 |
| **屏幕时长统计** | HyperIsland Kit | ^0.4.3 |
| **高级权限** | Shizuku | ^13.1.5 |

---

## 目录结构详解

```
math_quiz_app/
│
├── lib/                          # Flutter 源代码
│   ├── main.dart                 # 应用入口，初始化 + 路由控制
│   ├── models.dart               # 数据模型定义（Todo/Countdown/Question）
│   ├── storage_service.dart      # 核心：本地存储 + 增量同步逻辑
│   ├── update_service.dart       # 应用版本检查与更新下载
│   │
│   ├── screens/                  # 页面级组件（UI + 业务逻辑）
│   │   ├── login_screen.dart           # 登录/注册页
│   │   ├── home_dashboard.dart         # 🏠 主仪表盘（核心页面）
│   │   ├── settings_screen.dart        # 全局设置页
│   │   ├── home_settings_screen.dart   # 首页布局设置（含权限检查面板）
│   │   ├── math_menu_screen.dart       # 数学练习菜单
│   │   ├── quiz_screen.dart            # 答题页面
│   │   ├── course_screens.dart         # 课程表管理（周视图 + 导入）
│   │   ├── screen_time_detail_screen.dart  # 屏幕时长详情页
│   │   ├── historical_todos_screen.dart    # 历史待办 + 回收站
│   │   ├── historical_countdowns_screen.dart  # 历史倒计时
│   │   ├── pomodoro_screen.dart        # 🍅 番茄钟（工作台 + 统计看板）
│   │   ├── time_log_screen.dart        # 时间全览（包含番茄钟与时长周/日视图网格）
│   │   ├── other_screens.dart          # 排行榜与历史记录页面
│   │   └── upgrade_guide_screen.dart   # 版本升级引导页
│   │
│   ├── services/                 # 业务逻辑层（无 UI）
│   │   ├── api_service.dart            # 🌐 REST API 封装（含番茄钟接口）
│   │   ├── course_service.dart         # 课程表解析与管理
│   │   ├── screen_time_service.dart    # 屏幕时长统计
│   │   ├── notification_service.dart   # 推送通知服务（多渠道：待办/课程/番茄钟）
│   │   ├── pomodoro_service.dart       # 🍅 番茄钟核心服务（设置/运行状态/记录/标签）
│   │   ├── pomodoro_sync_service.dart  # 番茄钟跨设备 WebSocket 实时状态同步服务
│   │   ├── reminder_schedule_service.dart # 本地精确保活提醒调度池
│   │   ├── tai_service.dart            # Windows Tai 屏幕时间数据库解析器
│   │   ├── widget_service.dart         # 桌面小部件刷新
│   │   ├── external_share_handler.dart # 外部分享接收
│   │   ├── hfut_schedule_parser.dart   # 合肥工业大学课表解析器
│   │   ├── xmu_schedule_parser.dart    # 厦门大学课表解析器
│   │   └── xidian_schedule_parser.dart # 西安电子科技大学课表解析器
│   │
│   └── widgets/                  # 可复用 UI 组件
│       ├── home_sections.dart          # 主页分栏布局
│       ├── home_app_bar.dart           # 主页顶部导航
│       ├── countdown_section_widget.dart  # 倒计时卡片
│       ├── course_section_widget.dart     # 课程提醒卡片
│       ├── todo_section_widget.dart       # 待办清单卡片
│       └── pomodoro_today_section.dart    # 首页番茄钟今日统计简报
│
├── math-quiz-backend/            # Cloudflare Workers 后端
│   ├── src/
│   │   └── index.js              # API 路由（Auth/Sync/ScreenTime）
│   ├── schema.sql                # D1 数据库表结构
│   ├── wrangler.toml             # Workers 配置文件
│   └── package.json              # Node.js 依赖
│
├── android/                      # Android 原生配置
│   ├── app/
│   │   ├── build.gradle.kts      # Gradle 构建脚本
│   │   └── src/main/
│   │       ├── AndroidManifest.xml  # 权限声明
│   │       └── kotlin/              # 原生桥接代码
│
├── assets/                       # 静态资源
│   └── icon/                     # 应用图标
│
├── pubspec.yaml                  # Flutter 依赖配置
├── Readme.md                     # 项目简介
└── PROJECT_ARCHITECTURE.md       # 📘 本文档
```

### 📂 关键文件说明

#### **main.dart** - 应用生命周期管理
- **职责**：极速启动优化、主题切换监听、登录态检查
- **关键逻辑**：
  ```dart
  // 核心：先启动 UI 再异步初始化插件
  void main() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MyApp()); // 立即渲染，避免黑屏
  }
  ```

#### **models.dart** - 数据模型定义
- **核心类**：
  - `TodoItem`：待办事项（带版本控制字段）
  - `CountdownItem`：倒计时事件
  - `Question`：数学练习题目
  - `QuestionGenerator`：随机题目生成器
  - `CourseItem`：课程表条目

#### **storage_service.dart** - 数据持久化核心
- **职责**：本地存储 + 云端同步 + 业务逻辑
- **关键方法**：
  - `syncData()`: 增量同步引擎
  - `getTodos()` / `saveTodos()`: 待办数据读写
  - `syncAppMappings()`: 云端分类字典同步

#### **api_service.dart** - 网络请求封装
- **职责**：统一 HTTP 请求管理
- **接口分类**：
  - 认证：`register()` / `login()` / `changePassword()`
  - 同步：`postDeltaSync()` - 增量同步核心接口
  - 屏幕时间：`uploadScreenTime()` / `fetchScreenTime()`
  - 课程表：`uploadCourses()` / `fetchCourses()`
  - 工具：`fetchAppMappings()` - 应用分类字典
  - 番茄钟标签：`fetchPomodoroTags()` / `syncPomodoroTags()`
  - 番茄钟记录：`uploadPomodoroRecord()` / `uploadPomodoroRecords()` / `fetchPomodoroRecords()`
  - 番茄钟设置：`syncPomodoroSettings()` / `fetchPomodoroSettings()`

---

## 核心架构设计

### 🏛️ 分层架构

```
┌─────────────────────────────────────────┐
│          UI Layer (screens/widgets/)    │  ← 页面渲染 + 用户交互
├─────────────────────────────────────────┤
│       Business Logic Layer (services/)  │  ← 业务逻辑 + 数据处理
├─────────────────────────────────────────┤
│    Data Access Layer (storage_service)  │  ← 本地持久化 + 同步算法
├─────────────────────────────────────────┤
│      Network Layer (api_service)        │  ← HTTP 请求封装
├─────────────────────────────────────────┤
│        Backend (Cloudflare Workers)     │  ← Serverless API
└─────────────────────────────────────────┘
```

### 🔄 数据流向

#### **读取数据流程**
```
用户打开页面
    ↓
StatefulWidget.initState()
    ↓
StorageService.getTodos(username)
    ↓ 从 SharedPreferences 读取
检查是否需要日期重置（每日重复任务）
    ↓
返回数据给 UI
    ↓
setState() 触发重新渲染
```

#### **修改数据流程**
```
用户点击"完成"按钮
    ↓
更新 TodoItem 对象
    ↓
调用 item.markAsChanged()  // 版本号 +1，更新时间戳
    ↓
StorageService.saveTodos(username, todos, sync: true)
    ↓ 持久化到本地
触发 syncData(username)  // 自动同步到云端
    ↓ 打包脏数据（updatedAt > lastSyncTime）
ApiService.postDeltaSync()
    ↓ HTTP POST 请求
Cloudflare Workers 处理
    ↓ 返回服务器更新
合并远程数据（LWW 策略）
    ↓
再次持久化（sync: false，避免递归）
```

### 🔐 认证流程

```
用户输入邮箱/密码
    ↓
ApiService.login(email, password)
    ↓ 后端验证
返回 { success: true, token: "xxx", user: {...} }
    ↓
StorageService.saveLoginSession(username, token)
    ↓ 保存到 SharedPreferences
ApiService.setToken(token)  // 内存中持有 Token
    ↓
所有后续请求自动携带 Authorization: Bearer xxx
```

### 📡 增量同步算法 (Delta Sync)

#### **核心字段**
```dart
class TodoItem {
  String id;         // UUID，全局唯一
  int version;       // 并发版本号
  int updatedAt;     // 最后修改时间戳（UTC 毫秒，即 DateTime.now().millisecondsSinceEpoch）
  bool isDeleted;    // 逻辑删除标记
}
```

#### **⏰ 时间字段统一规范**

| 存储/传输 | 格式 | 说明 |
|---------|------|------|
| 本地 SharedPreferences | UTC 毫秒时间戳 (int) | `DateTime.now().millisecondsSinceEpoch` |
| 网络传输（JSON）| UTC 毫秒时间戳 (int) | Flutter ↔ Worker 均使用整数 |
| 云端数据库（D1）| UTC 毫秒时间戳 (int) | `Date.now()` |
| UI 显示 | 本地时间 | `DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal()` |

> **关键原则**：`DateTime.now().millisecondsSinceEpoch`（Dart）与 `Date.now()`（JS）都是 UTC epoch，天然一致，**无需任何 ±8h 偏移转换**。只有最终显示给用户时调用 `.toLocal()` 即可自动转为 CST(+8)。

#### **同步策略**
1. **客户端打包脏数据**：
   ```dart
   List<TodoItem> dirtyTodos = allLocalTodos
       .where((t) => t.updatedAt > lastSyncTime || t.isDeleted == true)
       .toList();
   ```

2. **服务器返回更新**：
   ```json
   {
     "success": true,
     "server_todos": [...],        // 其他设备的更新
     "new_sync_time": 1709884800000
   }
   ```

3. **LWW 冲突解决**：
   ```dart
   if (serverItem.version > localItem.version ||
       serverItem.updatedAt > localItem.updatedAt) {
     localItem = serverItem;  // 服务器数据胜出
   }
   ```

4. **逻辑删除处理**：
   - 客户端删除时：`item.isDeleted = true` + 同步到服务器
   - 其他设备收到：保留 tombstone 标记，UI 不显示
   - 回收站功能：查询 `isDeleted == true` 的数据

---

### 🍅 番茄钟系统架构

#### **模块组成**

```
pomodoro_screen.dart
├── _PomodoroScreen          # TabBar 容器（工作台 / 统计看板）
│   ├── _PomodoroWorkbench   # 专注工作台（不可滚动，居中计时器）
│   └── _PomodoroStats       # 统计看板（可滚动，日/月/年视图）
│
pomodoro_service.dart
├── PomodoroTag              # 标签数据模型
├── PomodoroRecord           # 专注记录数据模型
├── PomodoroSettings         # 偏好设置数据模型
├── PomodoroRunState         # 运行时状态（防误杀核心）
└── PomodoroService          # 核心服务（本地存储 + 增量同步）
```

#### **防误杀 / 状态恢复机制**

基于绝对时间戳，不依赖内存计时：

```
开始专注
    ↓
saveRunState({ phase: focusing, targetEndMs: now + duration })
    ↓ 写入 SharedPreferences
App 被杀 / 切后台
    ↓
重新进入番茄钟
    ↓
loadRunState() → 计算 remaining = targetEndMs - now
    ↓
remaining > 0 → 恢复计时，继续倒计时
remaining ≤ 0 → 直接触发专注结束逻辑
```

#### **任务 / 标签持久化规则**

| 状态 | 持久化位置 | Key |
|---|---|---|
| idle 时绑定的任务 | SharedPreferences | `pomodoro_idle_bound_todo_uuid` / `_title` |
| idle 时选中的标签 | SharedPreferences | `pomodoro_idle_selected_tag_uuids`（逗号分隔） |
| 专注/休息中的状态 | SharedPreferences | `pomodoro_run_state`（JSON） |

**关键规则**（防止任务丢失）：
1. 所有 `_persistIdleBoundTodo()` 调用必须 `await`，禁止 fire-and-forget
2. `_startFocus` 时序：**先写 RunState → 再清 idle key**（防止被杀后数据全丢）
3. 任何回到 idle 的路径（结束/放弃/跳过休息）：**先写 idle 持久化 → 再清 RunState**

#### **云端写操作规范（本地优先）**

所有涉及用户操作的写入必须遵循"本地优先"原则：

```
用户操作（增删改）
    ↓
await 本地保存（SharedPreferences）← 立即完成，UI 立刻响应
    ↓
fire-and-forget 云端上传          ← 后台异步，失败不影响 UI
    ↓
下次手动/自动同步时批量补传漏传的记录
```

| 方法 | 本地存储 | 云端同步 |
|---|---|---|
| `PomodoroService.addRecord()` | `await _saveRecords()` | `.catchError()` fire-and-forget |
| `PomodoroService.updateRecord()` | `await _saveRecords()` | `.catchError()` fire-and-forget |
| `PomodoroService.deleteRecord()` | `await _saveRecords()` | `.catchError()` fire-and-forget |
| `PomodoroService.saveSettings()` | `await prefs.setString()` | `.catchError()` fire-and-forget |
| `PomodoroService.saveTags()` → `onChanged` | `await saveTags()` | `.catchError()` fire-and-forget |
| `StorageService.saveTodos()` | `await prefs.setStringList()` | `Future.microtask(() => syncData())` |

#### **通知渠道体系**

```
Android 通知渠道
├── live_updates_official_v2    # 主通知（待办进度，IMPORTANCE_DEFAULT）
├── pomodoro_timer_low          # 番茄钟计时（IMPORTANCE_LOW，不唤屏，省电）
└── event_alert_v1              # 事件提醒（IMPORTANCE_DEFAULT，有震动，可同步手环）
    ├── 课程提醒（alertKey: 'course_xxx'）
    ├── 待办提醒（alertKey: 'todo_xxx'）
    ├── 番茄开始（alertKey: 'pomo_start_xxx'）
    └── 番茄结束（alertKey: 'pomo_end_xxx'）
```

**去重机制**：`event_alert_v1` 渠道用 SharedPreferences 存 `alertKey`，相同 key 只触发一次普通通知。

---

### 🗄️ 数据库表结构（Cloudflare D1）

#### **todos 表**
| 列 | 类型 | 说明 |
|---|---|---|
| `id` | INTEGER PK | 自增主键 |
| `user_id` | INTEGER | 用户 ID |
| `content` | TEXT | 待办内容 |
| `is_completed` | BOOLEAN | 是否完成 |
| `created_at` | INTEGER | 物理创建时间（UTC 毫秒时间戳） |
| `updated_at` | INTEGER | 最后修改时间（UTC 毫秒时间戳） |
| `is_deleted` | BOOLEAN | 逻辑删除标记 |
| `due_date` | INTEGER | 截止时间（UTC 毫秒，可为 null） |
| `created_date` | INTEGER | **任务开始时间**（UTC 毫秒，可为 null，≠ created_at） |
| `version` | INTEGER | 并发版本号 |
| `device_id` | TEXT | 最后修改设备 ID |
| `uuid` | TEXT | 全局唯一标识（Flutter 端主键） |
| `recurrence` | INTEGER | 重复类型（0=不重复，1=每日，2=每周...） |
| `custom_interval_days` | INTEGER | 自定义重复间隔（天） |
| `recurrence_end_date` | INTEGER | 重复结束日期（UTC 毫秒） |
| `remark` | TEXT | 📝 备注内容（可为 null） |

> ⚠️ **`created_date` vs `created_at`**：  
> `created_at` = 记录被创建的物理时间（不可变）  
> `created_date` = 用户设定的任务开始时间（可编辑，对应 Flutter 端 `TodoItem.createdDate`）

#### **countdowns 表**
| 列 | 类型 | 说明 |
|---|---|---|
| `id` | INTEGER PK | 自增主键 |
| `user_id` | INTEGER | 用户 ID |
| `title` | TEXT | 标题 |
| `target_time` | INTEGER | 目标时间（UTC 毫秒时间戳） |
| `created_at` | INTEGER | 创建时间（UTC 毫秒） |
| `updated_at` | INTEGER | 更新时间（UTC 毫秒） |
| `is_deleted` | BOOLEAN | 逻辑删除 |
| `device_id` | TEXT | 设备 ID |
| `version` | INTEGER | 版本号 |
| `uuid` | TEXT | 全局唯一标识 |

#### **番茄钟相关表**

| 表名 | 用途 |
|---|---|
| `pomodoro_tags` | 用户自定义标签（支持 Delta Sync） |
| `todo_tags` | 待办与标签多对多关联 |
| `pomodoro_records` | 专注记录（start_time/end_time/status） |
| `pomodoro_settings` | 用户偏好（专注时长/休息时长/循环次数） |

```sql
-- pomodoro_records 关键字段
uuid TEXT PRIMARY KEY,
user_id INTEGER NOT NULL,
todo_uuid TEXT,           -- 关联 todos.uuid（可为 null：自由专注）
start_time INTEGER,       -- UTC 毫秒
end_time INTEGER,         -- UTC 毫秒（null = 进行中）
planned_duration INTEGER, -- 计划时长（秒）
actual_duration INTEGER,  -- 实际时长（秒）
status TEXT,              -- 'completed' | 'interrupted' | 'switched'
device_id TEXT,
is_deleted INTEGER,
version INTEGER
```

### 📝 命名约定

| 类型 | 规范 | 示例 |
|------|------|------|
| **文件名** | 蛇形命名 | `home_dashboard.dart` |
| **类名** | 大驼峰 | `HomeDashboard` |
| **变量/方法** | 小驼峰 | `currentUser` / `loadData()` |
| **常量** | 全大写下划线 | `KEY_CURRENT_USER` |
| **私有成员** | 下划线前缀 | `_isSyncing` / `_loadData()` |

### 🎨 代码风格

#### **异步编程**
✅ **推荐**：使用 `async/await`
```dart
Future<void> _loadData() async {
  final todos = await StorageService.getTodos(username);
  if (mounted) {  // 避免组件销毁后调用 setState
    setState(() { _todos = todos; });
  }
}
```

❌ **避免**：嵌套 `Future.then()`
```dart
// 不推荐：回调地狱
StorageService.getTodos(username).then((todos) {
  setState(() { _todos = todos; });
}).catchError((e) { /* ... */ });
```

#### **云端写操作：本地优先原则**

> **核心规范**：任何涉及用户数据的写操作，必须先完成本地存储，再 fire-and-forget 上传云端。禁止在用户操作路径上 `await` 网络请求。

✅ **正确做法**：
```dart
// 本地保存立即返回，云端上传后台进行
Future<void> saveMyData(MyModel data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('key', jsonEncode(data.toJson())); // ← await 本地
  ApiService.uploadMyData(data.toJson()).catchError((_) => false); // ← fire-and-forget
}
```

❌ **错误做法**（会导致 UI 卡顿）：
```dart
Future<void> saveMyData(MyModel data) async {
  await prefs.setString('key', jsonEncode(data.toJson()));
  await ApiService.uploadMyData(data.toJson()); // ← ❌ 在用户操作路径上 await 网络
}
```

**例外**：以下场景允许 `await` 网络：
- 用户主动触发的"手动同步"（有 loading 状态指示）
- 登录/注册（必须等待服务器响应）
- 课程表上传（有 loading dialog）

#### **错误处理**
```dart
try {
  await ApiService.login(email, password);
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('操作失败: $e')),
    );
  }
}
```

#### **组件生命周期**
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);  // 监听前后台切换
  _loadAllData();
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _timer?.cancel();  // 清理 Timer
  super.dispose();
}
```

### 🗂️ 文件组织原则

1. **单一职责**：一个文件只负责一个核心功能
2. **行数限制**：单文件建议不超过 800 行，超过则拆分
3. **导入顺序**：
   ```dart
   // 1. Dart 标准库
   import 'dart:convert';
   
   // 2. Flutter 框架
   import 'package:flutter/material.dart';
   
   // 3. 第三方包
   import 'package:shared_preferences/shared_preferences.dart';
   
   // 4. 项目内部
   import '../models.dart';
   import '../storage_service.dart';
   ```

---

## 常见开发场景

### 🆕 场景一：新增一个页面

#### **步骤 1：创建页面文件**
```dart
// lib/screens/my_new_screen.dart

import 'package:flutter/material.dart';
import '../storage_service.dart';
import '../models.dart';

class MyNewScreen extends StatefulWidget {
  final String username;
  const MyNewScreen({super.key, required this.username});

  @override
  State<MyNewScreen> createState() => _MyNewScreenState();
}

class _MyNewScreenState extends State<MyNewScreen> {
  bool _isLoading = true;
  List<TodoItem> _data = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await StorageService.getTodos(widget.username);
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新页面')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _data.length,
              itemBuilder: (context, index) {
                return ListTile(title: Text(_data[index].title));
              },
            ),
    );
  }
}
```

#### **步骤 2：添加路由跳转**
```dart
// 在任意页面中跳转
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => MyNewScreen(username: widget.username),
  ),
);
```

---

### 🌐 场景二：调用后端 API

#### **步骤 1：在 api_service.dart 添加接口**
```dart
// lib/services/api_service.dart

static Future<Map<String, dynamic>> fetchMyData(int userId) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/my_endpoint?user_id=$userId'),
      headers: _getHeaders(),  // 自动注入 Token
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      return {'success': false, 'message': '请求失败'};
    }
  } catch (e) {
    return {'success': false, 'message': '网络错误: $e'};
  }
}
```

#### **步骤 2：在 UI 层调用**
```dart
Future<void> _fetchData() async {
  final prefs = await SharedPreferences.getInstance();
  int? userId = prefs.getInt('current_user_id');
  
  if (userId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先登录')),
    );
    return;
  }
  
  final result = await ApiService.fetchMyData(userId);
  
  if (result['success'] == true) {
    // 处理成功情况
    setState(() { _data = result['data']; });
  } else {
    // 显示错误信息
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['message'] ?? '未知错误')),
    );
  }
}
```

---

### 📦 场景三：新增数据模型

#### **步骤 1：在 models.dart 定义模型**
```dart
// lib/models.dart

class MyNewModel {
  String id;
  String content;
  int version;
  int updatedAt;
  int createdAt;
  bool isDeleted;

  MyNewModel({
    String? id,
    required this.content,
    this.version = 1,
    int? updatedAt,
    int? createdAt,
    this.isDeleted = false,
  }) :
    this.id = id ?? const Uuid().v4(),
    this.updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    this.createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  // 🚀 核心方法：每次修改必须调用
  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  // JSON 序列化
  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'version': version,
    'updated_at': updatedAt,
    'created_at': createdAt,
    'is_deleted': isDeleted ? 1 : 0,
  };

  // JSON 反序列化
  factory MyNewModel.fromJson(Map<String, dynamic> json) {
    return MyNewModel(
      id: json['id']?.toString() ?? const Uuid().v4(),
      content: json['content'] ?? '',
      version: json['version'] ?? 1,
      updatedAt: json['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: json['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: json['is_deleted'] == 1,
    );
  }
}
```

#### **步骤 2：在 storage_service.dart 添加读写方法**
```dart
// lib/storage_service.dart

static const String KEY_MY_DATA = "user_my_data";

static Future<void> saveMyData(String username, List<MyNewModel> items) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> jsonList = items.map((e) => jsonEncode(e.toJson())).toList();
  await prefs.setStringList("${KEY_MY_DATA}_$username", jsonList);
}

static Future<List<MyNewModel>> getMyData(String username) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> list = prefs.getStringList("${KEY_MY_DATA}_$username") ?? [];
  return list.map((e) => MyNewModel.fromJson(jsonDecode(e))).toList();
}
```

---

### 🔧 场景四：新增课程表解析器（新学校）

#### **步骤 1：创建解析器文件**
```dart
// lib/services/myschool_schedule_parser.dart

import '../services/course_service.dart';

class MySchoolScheduleParser {
  // 校验是否为该学校的格式
  static bool isValid(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      return data['school_code'] == 'MYSCHOOL';  // 特征字段
    } catch (e) {
      return false;
    }
  }

  // 解析逻辑
  static List<CourseItem> parse(String jsonString) {
    List<CourseItem> courses = [];
    try {
      final data = jsonDecode(jsonString);
      
      for (var lesson in data['lessons']) {
        courses.add(CourseItem(
          courseName: lesson['name'],
          teacherName: lesson['teacher'],
          date: lesson['date'],
          weekday: lesson['weekday'],
          startTime: lesson['start_time'],  // 格式：830 表示 08:30
          endTime: lesson['end_time'],
          weekIndex: lesson['week'],
          roomName: lesson['room'],
        ));
      }
      
      return courses;
    } catch (e) {
      debugPrint("解析失败: $e");
      return [];
    }
  }
}
```

#### **步骤 2：在 course_service.dart 注册**
```dart
// lib/services/course_service.dart

import 'myschool_schedule_parser.dart';

static Future<bool> importScheduleFromJson(String jsonString) async {
  // 依次尝试各个解析器
  if (HfutScheduleParser.isValid(jsonString)) {
    return _parseAndSave(HfutScheduleParser.parse(jsonString));
  } else if (XmuScheduleParser.isValid(jsonString)) {
    return _parseAndSave(XmuScheduleParser.parse(jsonString));
  } else if (MySchoolScheduleParser.isValid(jsonString)) {  // 新增
    return _parseAndSave(MySchoolScheduleParser.parse(jsonString));
  }
  
  return false;
}
```

---

### 🎨 场景五：修改主题配色

#### **修改 Seed Color（主色调）**
```dart
// lib/main.dart

theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.purple,  // 修改为你想要的颜色
    brightness: Brightness.light,
  ),
  useMaterial3: true,
),
darkTheme: ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.purple,  // 保持一致
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
),
```

#### **添加自定义颜色**
```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: Brightness.light,
  ).copyWith(
    primary: Color(0xFF1E88E5),      // 自定义主色
    secondary: Color(0xFFFF6F00),    // 自定义辅助色
  ),
  useMaterial3: true,
),
```

---

## 已知技术债与注意事项

### 🚨 P0 级（紧急）

#### **1. 待办时间映射错误**
**文件**: `lib/screens/course_screens.dart` (约 100-450 行)

**问题描述**:  
待办事项的开始时间 `14:30-15:00` 在课程表周视图中被错误映射到 `15:00-15:50` 的课程时段。

**根本原因**:
```dart
// 待办的时间格式（毫秒时间戳）
DateTime start = DateTime.fromMillisecondsSinceEpoch(todo.createdAt);

// 课程的时间格式（整数）
startTime: 1430  // 表示 14:30

// 渲染时的转换逻辑可能有误差
double _timeToY(int hour, int minute, double minuteHeight) {
  if (hour < startHour) return 0;
  return ((hour - startHour) * 60 + minute) * minuteHeight;
}
```

**建议修复**:
1. 统一时间转换函数，确保待办和课程使用相同的坐标计算逻辑
2. 添加单元测试验证时间映射准确性
3. 检查是否有时区转换问题（UTC vs 本地时间）

---

### 🟠 P1 级（重要）

#### **2. 日期重置逻辑性能问题**
**文件**: `lib/storage_service.dart` (约 280-320 行)

**问题描述**:  
每次调用 `getTodos()` 时都会全量遍历待办列表，检查是否需要重置每日任务。

**性能影响**:
- 待办数量 < 50：无明显影响
- 待办数量 100+：主线程卡顿 50-200ms

**优化方案**:
```dart
// 方案 1：使用后台定时任务
WorkManager.schedule(() async {
  final todos = await getTodos(username);
  for (var todo in todos) {
    if (needReset(todo)) {
      todo.isDone = false;
      todo.markAsChanged();
    }
  }
  await saveTodos(username, todos);
}, schedule: "0 0 * * *");  // 每日凌晨执行

// 方案 2：缓存上次检查日期
static DateTime? _lastResetCheck;
if (_lastResetCheck == null || !_isSameDay(_lastResetCheck!, DateTime.now())) {
  // 执行重置逻辑
  _lastResetCheck = DateTime.now();
}
```

---

#### **3. 屏幕时间权限被拒无降级方案**
**文件**: `lib/services/screen_time_service.dart`

**问题描述**:  
用户拒绝 `PACKAGE_USAGE_STATS` 权限后，屏幕时间功能完全不可用，且无友好提示。

**改进建议**:
```dart
if (!hasPermission) {
  // 显示降级 UI
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.block, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Text('屏幕时间统计需要权限'),
        ElevatedButton(
          child: Text('授予权限'),
          onPressed: () => openAppSettings(),
        ),
      ],
    ),
  );
}
```

---

### 🟡 P2 级（可优化）

#### **4. home_dashboard.dart 文件过大**
**当前行数**: 721 行  
**建议**: 拆分为多个子组件

**重构方案**:
```
home_dashboard.dart (主文件，200 行)
├── home_dashboard_header.dart (顶部信息)
├── home_dashboard_course_section.dart (课程卡片)
├── home_dashboard_todo_section.dart (待办卡片)
└── home_dashboard_screen_time.dart (屏幕时间卡片)
```

---

#### **5. 并发冲突去重仅按时间戳**
**文件**: `lib/storage_service.dart` (约 227-275 行)

**问题**:  
虽然数据模型有 `version` 字段，但实际去重逻辑只用了 `updatedAt`。

**风险场景**:  
两个设备在同一毫秒内修改同一待办，会丢失其中一个版本。

**完整修复**:
```dart
if (existing == null || 
    item.version > existing.version ||
    (item.version == existing.version && item.updatedAt > existing.updatedAt)) {
  dedupeMap[item.id] = item;
}
```

---

### 🔵 P3 级（已知限制）

#### **6. 课程表解析器脆弱性**
**问题**: 教务系统格式变更会导致解析失败，且无通用异常捕获。

**改进方向**:
```dart
static Future<bool> importScheduleFromJson(String jsonString) async {
  try {
    // 尝试各个解析器
    if (HfutScheduleParser.isValid(jsonString)) {
      return _parseAndSave(HfutScheduleParser.parse(jsonString));
    }
    // ... 其他解析器
    
    // 全部失败
    throw Exception('不支持的课程表格式');
  } catch (e) {
    // 统一错误处理
    debugPrint("课程表解析失败: $e");
    return false;
  }
}
```

---

## 调试与部署

### 🔍 调试技巧

#### **查看本地存储数据**
```dart
final prefs = await SharedPreferences.getInstance();
debugPrint("所有存储键: ${prefs.getKeys()}");
debugPrint("待办数据: ${prefs.getStringList('user_todos_$username')}");
```

#### **重置用户数据（调试模式）**
```dart
// 方法 1：清空本地缓存
await prefs.clear();

// 方法 2：调用后端重置接口
await ApiService.debugResetDatabase();
```

#### **查看网络请求**
```dart
// 在 api_service.dart 的 _getHeaders() 添加日志
static Map<String, String> _getHeaders() {
  final headers = {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };
  debugPrint("请求头: $headers");
  return headers;
}
```

#### **性能分析**
```dart
import 'package:flutter/foundation.dart';

final stopwatch = Stopwatch()..start();
await heavyOperation();
debugPrint("耗时: ${stopwatch.elapsedMilliseconds}ms");
```

---

### 🚀 部署流程

#### **移动端构建**

##### Android APK
```bash
# Debug 版本（开发测试）
flutter build apk --debug

# Release 版本（正式发布）
flutter build apk --release

# 输出位置
# build/app/outputs/flutter-apk/app-release.apk
```

##### Android App Bundle (推荐)
```bash
flutter build appbundle --release

# 输出位置
# build/app/outputs/bundle/release/app-release.aab
```

##### iOS
```bash
flutter build ios --release

# 需在 Xcode 中配置签名后打包
```

---

#### **后端部署 (Cloudflare Workers)**

##### 初始化数据库
```bash
cd math-quiz-backend

# 创建 D1 数据库
npx wrangler d1 create math_quiz_db

# 执行 Schema
npx wrangler d1 execute math_quiz_db --remote --file=./schema.sql
```

##### 部署 Worker
```bash
# 测试环境
npx wrangler dev

# 生产环境
npx wrangler deploy
```

##### 更新环境变量
```bash
# 在 wrangler.toml 中配置
[[d1_databases]]
binding = "DB"
database_name = "math_quiz_db"
database_id = "你的数据库ID"

[vars]
RESEND_API_KEY = "re_xxxx"  # 邮件服务密钥
```

---

### 📊 版本管理

#### **Flutter 应用版本**
```yaml
# pubspec.yaml
version: 1.7.1+17  # 格式：主版本.次版本.修订号+构建号
```

#### **版本号规范**
- **主版本号** (1.x.x): 重大架构变更或不兼容更新
- **次版本号** (x.7.x): 新功能添加
- **修订号** (x.x.1): Bug 修复
- **构建号** (+17): 每次构建自增

---

### 🧪 测试建议

#### **单元测试**
```dart
// test/models_test.dart
import 'package:test/test.dart';
import 'package:math_quiz_app/models.dart';

void main() {
  test('TodoItem 版本号递增', () {
    final todo = TodoItem(title: '测试');
    final oldVersion = todo.version;
    
    todo.markAsChanged();
    
    expect(todo.version, oldVersion + 1);
  });
}
```

#### **集成测试**
```dart
// test/storage_service_test.dart
test('同步数据保持一致性', () async {
  final username = 'test_user';
  
  // 创建本地数据
  await StorageService.saveTodos(username, [
    TodoItem(title: '任务1'),
  ]);
  
  // 模拟同步
  await StorageService.syncData(username);
  
  // 验证
  final todos = await StorageService.getTodos(username);
  expect(todos.length, 1);
});
```

---

## 常见问题 FAQ

### Q1: 如何修改后端 API 地址？
**A**: 修改 `lib/services/api_service.dart` 的 `baseUrl` 常量
```dart
static const String baseUrl = "https://your-domain.com";
```

### Q2: 如何禁用自动同步？
**A**: 在 `lib/storage_service.dart` 中修改
```dart
// 所有 sync: true 改为 sync: false
await saveTodos(username, todos, sync: false);
```

### Q3: 如何添加新的主题模式（如护眼模式）？
**A**: 扩展 `StorageService.themeNotifier` 的可选值
```dart
// 1. 在 storage_service.dart 添加新模式
static const String THEME_EYE_CARE = 'eye_care';

// 2. 在 main.dart 添加主题定义
ThemeMode getThemeMode(String mode) {
  switch (mode) {
    case 'light': return ThemeMode.light;
    case 'dark': return ThemeMode.dark;
    case 'eye_care': return ThemeMode.light;  // 使用自定义配色
    default: return ThemeMode.system;
  }
}

// 3. 自定义护眼主题
if (themeModeString == 'eye_care') {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.light,
      ).copyWith(
        surface: Color(0xFFF5F5DC),  // 米黄色背景
      ),
    ),
  );
}
```

### Q4: 如何导出用户数据？
**A**: 添加导出功能
```dart
Future<void> exportUserData(String username) async {
  final todos = await StorageService.getTodos(username);
  final countdowns = await StorageService.getCountdowns(username);
  
  final exportData = {
    'version': '1.0',
    'export_time': DateTime.now().toIso8601String(),
    'todos': todos.map((e) => e.toJson()).toList(),
    'countdowns': countdowns.map((e) => e.toJson()).toList(),
  };
  
  final jsonString = jsonEncode(exportData);
  
  // 使用 file_picker 保存到本地
  await FilePicker.platform.saveFile(
    fileName: 'backup_$username.json',
    bytes: utf8.encode(jsonString),
  );
}
```

### Q5: 如何适配平板电脑的大屏幕？
**A**: 使用 LayoutBuilder 响应式布局
```dart
@override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth > 600) {
        // 平板布局：双栏
        return Row(
          children: [
            Expanded(child: _buildLeftColumn()),
            Expanded(child: _buildRightColumn()),
          ],
        );
      } else {
        // 手机布局：单栏
        return Column(
          children: [
            _buildLeftColumn(),
            _buildRightColumn(),
          ],
        );
      }
    },
  );
}
```

---

## 贡献指南

### 提交规范
```
类型(范围): 简短描述

详细说明（可选）

关联 Issue: #123
```

**类型**:
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式调整
- `refactor`: 重构
- `perf`: 性能优化
- `test`: 测试相关

**示例**:
```
feat(course): 添加清华大学课程表解析器

- 支持 TsinghuaScheduleParser
- 兼容 ICS 格式导入
- 添加单元测试

关联 Issue: #456
```

---

## 更新日志

### v1.8.4 (2026-03-08) 🔧 番茄钟稳定性全面修复

#### 任务/标签持久化修复
- 🐛 **修复所有 `_persistIdleBoundTodo()` 缺少 `await` 导致的任务丢失**
  - `_showBindTodoDialog` 选任务、FilterChip 打标签、`_onFocusEnd`、`_onBreakEnd`、跳过休息等路径全部补 `await`
  - `_startFocus` 时序调整：先 `saveRunState` 再清 idle key（防被杀后数据全丢）
  - `_onFocusEnd` / `_finishEarly` / `_abandonFocus` / `_handleBreakEndFromBackground` 均遵循"先写 idle → 再清 RunState"顺序
  - `_handleBreakEndFromBackground` 补充从 `saved` 恢复 `_boundTodo` 和 `tagUuids` 逻辑
  - 标签恢复时去掉 `validTagUuids` 过滤，直接读持久化列表（防 `_allTags` 为空时全部标签被清空）

#### 云端同步修复
- 🐛 **修复专注记录 `device_id` 为空**：`_PomodoroWorkbenchState` 新增 `_deviceId` 字段，`_init()` 调用 `StorageService.getDeviceId()` 获取，创建 `PomodoroRecord` 时传入
- ✨ **`addRecord` 改为本地优先**：本地保存后立即返回，云端上传 fire-and-forget；上传成功后更新 `_keyLastRecordUpload` 时间戳
- ✨ **`syncRecordsToCloud` 改为增量上传**：只上传 `updatedAt > lastUploadTime` 的记录，避免全量重复上传
- ✨ **`updateRecord` / `deleteRecord` 改为本地优先**：本地保存立即返回，云端上传后台进行
- ✨ **标签管理 `onChanged` 改为本地优先**：`await saveTags()` 后 fire-and-forget `syncTagsToCloud()`，操作不再卡顿

#### UI 修复
- 🐛 **修复统计看板顶部留白**：去掉 `extendBodyBehindAppBar`，改用自绘导航栏 + `SafeArea` 精确控制布局
- 🐛 **修复底部 Tab 与系统导航栏打架**：`bottomNavigationBar` 改为内联在 `Column` 底部，包裹 `SafeArea(top: false)`
- ✨ **番茄钟去掉系统 AppBar**：完全自绘顶部栏，idle 时右侧显示设置/标签按钮，专注时左侧显示返回按钮
- 🐛 **修复编辑专注记录保存按钮无响应感**：`updateRecord` 改为本地优先后 `Navigator.pop` 立即执行，体感响应极快

---

### v1.8.3 (2026-03-07) 🍅 番茄钟功能完善

- ✨ **待办备注字段 (`remark`)**：todos 表新增 `remark TEXT` 列，Flutter 端 `TodoItem` 同步更新
  - 新增/编辑待办时支持填写备注
  - 待办列表卡片显示备注副标题
  - 通知栏（全天/时段/全天备注）均支持副标题显示
- ✨ **番茄钟专注通知低功耗优化**：独立 `pomodoro_timer_low` 渠道，≥1 分钟时每分钟更新一次，最后 60 秒才逐秒更新
- ✨ **多通知渠道**：普通提醒（事件、课程、番茄开始/结束）走 `event_alert_v1` 渠道，同步手环；计时走低功耗渠道
- ✨ **专注记录本地优先加载**：打开统计看板先展示本地缓存，增量同步后刷新

---

### v1.8.2 (2026-03-06) 🍅 番茄钟系统上线

- ✨ **番茄钟专注工作台**：自定义专注/休息时长、循环次数，不可滚动固定布局
- ✨ **任务绑定系统**：专注前或专注中可绑定待办事项，切换任务时计时不重置（分段记录）
- ✨ **自定义标签**：支持多标签绑定，云端 Delta Sync 同步
- ✨ **防误杀恢复机制**：基于绝对时间戳，App 被杀后重启自动恢复剩余时间
- ✨ **完成确认 + 状态同步**：专注结束主动询问，确认后自动标记待办完成并同步云端
- ✨ **统计看板**：日/月/年维度，标签分布，专注明细，支持编辑和删除记录
- ✨ **首页"最近专注"模块**：今日无记录则展示昨日记录，点击跳转统计看板
- ✨ **D1 数据库扩展**：新增 `pomodoro_tags`、`todo_tags`、`pomodoro_records`、`pomodoro_settings` 表

---

### v1.7.3 (2026-03-06) ⏰ 时间规范统一
- 🔧 **统一所有时间字段为 UTC 毫秒时间戳**
  - 废弃历史 ISO 字符串格式兼容代码
  - `models.dart`：`_parseTimestamp` / `_parseDateField` 简化为纯整数解析；`toJson` 中所有 `DateTime` 转毫秒去掉多余的 `.toLocal()`
  - `index.js`：`normalizeToMs` 简化为纯数字解析；`due_date` / `created_date` / `target_time` 接收端去掉 ISO +08:00 补偿逻辑
  - 显示层统一：`DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal()`
  - 忽略旧历史数据，新数据从此无时区偏差问题

### v1.7.2 (2026-03-06) 🔥 重要修复版本
- 🐛 **修复 created_at 与 created_date 混淆问题**（核心 Bug）
  - 新增 `created_date` 字段区分物理创建时间与业务开始时间
  - 修复课程表待办时间映射错误（14:30-15:00 不再显示为 15:00-15:50）
  - 更新后端数据库表结构和同步 API
  - 全面修正 7 个 UI 文件的时间读取逻辑
  - 完整向后兼容旧数据
- 📝 新增完整修复文档：`BUGFIX_CREATED_DATE.md`
- 📝 新增部署指南：`DEPLOYMENT_GUIDE.md`

### v1.7.1 (2026-03-06)
- 🐛 修复屏幕时间统计权限异常
- ✨ 新增学期进度条功能
- 🎨 优化深色模式配色
- 📝 完善项目架构文档

### v1.7.0 (2026-02-20)
- ✨ 支持西安电子科技大学课程表导入
- 🚀 优化增量同步性能
- 🔧 修复课程表时区转换问题

---

## 联系方式

- **项目主页**: [GitHub](https://github.com/Junpgle/CountdownTodo)
- **问题反馈**: [Issues](https://github.com/Junpgle/CountdownTodo/issues)
- **技术讨论**: [Discussions](https://github.com/Junpgle/CountdownTodo/discussions)

---

**文档维护者**: Junpgle  
**最后更新**: 2026-03-17  
**文档版本**: v2.1.6

---

> 💡 **提示**: 当你在新的 AI 会话中需要快速了解项目架构时，只需让 AI 阅读本文档，即可获得完整的上下文信息。

> 🔄 **更新频率**: 建议每次重大版本发布时同步更新本文档。
