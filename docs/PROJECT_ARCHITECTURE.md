# 项目架构文档 - CountDownTodo

## 📌 项目概述

**CountDownTodo** 是一个跨平台效率工具应用，核心功能包括：
- 待办事项 (Todo) 管理 — 支持 LLM 智能解析、图片识别、自然语言输入
- 重要日倒计时 (Countdown)
- 番茄钟 (Pomodoro) 专注计时 — 标签管理、跨端 WebSocket 同步
- 数学测验 (Math Quiz)
- 屏幕使用时间统计 (Screen Time)
- 课表管理 (Course Schedule) — 支持 4 种院校格式
- 多端数据同步 (Cloud Sync) — Delta Sync 增量同步
- Windows 桌面灵动岛 (Dynamic Island)
- 手环同步 (Band Sync)
- 时间日志 (Time Log)

## 2026-05-24 当前实现快照

- 当前应用版本：`4.12.19`。
- 主 Flutter 代码位于 `lib/`，当前包含 `screens/`、`services/`、`widgets/`、`course_import/`、`windows_island/` 等模块。
- 高容量业务数据已以 SQLite 为主存储，`SharedPreferences` 主要保留设置、登录态、水位线、兼容迁移和少量轻量缓存。
- 同步主入口仍是 `StorageService.syncData()`，番茄钟标签/记录由 `PomodoroService` 走独立同步链路。
- 新后端能力应优先落到 `aliyun_debug/`；`math-quiz-backend/` 的 Cloudflare Worker 保留兼容路径。
- Web 通过 Cloudflare Zero Trust 访问 `https://api-cdt.junpgle.me/`；Windows/Android 可直接访问 Alibaba Cloud HTTP 服务。
- Windows island / floating-window 逻辑是 Windows-only，Android 不应导入或初始化相关模块。

---

## 🛠 技术栈概览

| 类别 | 技术 | 说明 |
|------|------|------|
| **框架** | Flutter 3.x | 跨平台 UI 框架 |
| **语言** | Dart (SDK >=3.1.0 <4.0.0) | 空安全 |
| **UI 库** | Material Design 3 | `useMaterial3: true` |
| **状态管理** | ValueListenable + setState + Stream | 无第三方状态管理库 |
| **本地存储** | SQLite + SharedPreferences | SQLite 承载高容量业务数据；SharedPreferences 保留设置、登录态、水位线和兼容迁移 |
| **网络请求** | http 包 | 封装在 `ApiService` |
| **后端** | Alibaba Cloud + Cloudflare Worker | 新功能优先 Alibaba Cloud；Cloudflare Worker 保留兼容 |
| **同步协议** | Delta Sync + Oplog | LWW、版本冲突、客户端本地日程冲突、规划块同步 |
| **实时通信** | WebSocket | 番茄钟跨端感知和协同同步信号 |
| **桌面窗口** | desktop_multi_window + window_manager | 灵动岛独立进程 |

### 关键依赖项
```yaml
# 核心
http: ^1.2.0              # HTTP 客户端
shared_preferences: ^2.5.5 # 设置、登录态、水位线和轻量缓存
web_socket_channel: ^3.0.1 # WebSocket 通信
uuid: ^4.2.2               # 全局唯一 ID 生成
cached_network_image: ^3.3.0 # 图片缓存
intl: ^0.20.2              # 国际化 & 时间格式化

# 通知 & 权限
flutter_local_notifications: ^20.0.0 # 本地通知
permission_handler: ^12.0.1          # 权限管理
device_info_plus: ^12.4.0            # 设备信息

# 桌面端
window_manager: ^0.5.0     # 桌面窗口管理
desktop_multi_window: ^0.3.0 # 多窗口支持
ffi: ^2.1.2                # FFI 基础库
win32: ^5.15.0             # Win32 API

# 文件 & 媒体
file_picker: ^10.3.10      # 文件选择
receive_sharing_intent: ^1.8.1 # 外部分享接收
video_player: ^2.11.1      # 视频播放
flutter_image_compress: ^2.3.0 # 图片压缩

# AI & Markdown
flutter_markdown: ^0.7.1   # Markdown 渲染
html: ^0.15.4              # HTML 解析

# 桌面端 SQLite
sqflite_common_ffi: ^2.3.0 # 桌面端 SQLite 读取
```

---

## 📂 目录结构说明

当前目录以实际代码为准，不再在文档里维护易过期的精确文件数量。

```text
lib/
├── main.dart                 # 应用入口、插件初始化、路由和平台分流
├── models.dart               # 核心数据模型：待办、倒数日、时间日志、课程、规划块、冲突等
├── storage_service.dart      # SQLite 主存储、oplog、增量同步、冲突处理
├── update_service.dart       # 版本检查、下载和安装
├── course_import/            # 课程导入处理器、解析器和导入 UI
├── models/                   # AI action、聊天消息、勋章 ML 模型等扩展模型
├── screens/                  # 全屏页面和功能页
│   ├── pomodoro/             # 番茄钟工作台、统计页和专用组件
│   └── settings/             # 设置页、设置区块、弹窗和处理器
├── services/                 # API、数据库、同步、番茄钟、AI、课程、通知、平台服务
├── utils/                    # 导航、时区、动效和页面转场工具
├── widgets/                  # 首页区块和可复用 UI 组件
└── windows_island/           # Windows-only 灵动岛/悬浮窗模块
```

仓库级目录：

```text
aliyun_debug/                 # Alibaba Cloud 调试后端，新后端能力优先修改这里
math-quiz-backend/            # Cloudflare Worker 后端，保留兼容行为
CountDownTodo-band/           # 小米手环伴侣应用
android/ windows/ macos/ ios/ linux/ web/  # 平台壳
assets/ splash/ wallpaper/    # 资源目录
scripts/                      # 构建和运行脚本
docs/                         # 文档归档和索引
```
---

## 🔧 核心开发规范

### 1. 添加新页面

```dart
// 1. 在 lib/screens/ 创建新页面文件
class NewPage extends StatefulWidget {
  const NewPage({super.key});
  @override
  State<NewPage> createState() => _NewPageState();
}

// 2. 在 main.dart 中注册路由 (如需命名路由)
routes: {
  '/new-page': (context) => const NewPage(),
},

// 3. 页面跳转方式
Navigator.push(context, MaterialPageRoute(builder: (_) => NewPage()));
// 或
Navigator.pushNamed(context, '/new-page');
```

### 2. 调用后端 API

```dart
// 1. 在 ApiService 中添加静态方法
static Future<Map<String, dynamic>> fetchSomething(int id) async {
  try {
    final response = await _client.get(
      Uri.parse('$_effectiveBaseUrl/api/something?id=$id'),
      headers: _getHeaders(),  // 自动携带 Token
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    return {'success': false};
  } catch (e) {
    return {'success': false, 'message': e.toString()};
  }
}

// 2. 在页面/服务中调用
final result = await ApiService.fetchSomething(123);
if (result['success'] == true) {
  // 处理成功逻辑
}
```

### 3. 数据模型约定

```dart
// 所有可同步数据模型必须包含以下字段
class MyItem {
  String id;          // UUID v4
  int version;        // 并发版本号
  int updatedAt;      // UTC 毫秒时间戳
  int createdAt;      // UTC 毫秒时间戳
  bool isDeleted;     // 逻辑删除标记

  // 每次修改必须调用
  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }
}
```

### 4. 本地存储模式

```dart
// 高容量业务数据统一走 StorageService / DatabaseHelper
await StorageService.saveTodos(username, items);
final items = await StorageService.getTodos(username);

// 设置、登录态、水位线和轻量缓存继续使用 SharedPreferences。
// 大体量 JSON 镜像不要重新写回 SharedPreferences，避免 Android 插件层 OOM。
```

---

## 🎨 样式约定

### 颜色系统
- 使用 Material 3 的 `ColorScheme.fromSeed` 生成主题色
- 登录页等特殊页面使用自定义 `_T` 类定义颜色令牌
- 支持深色/浅色模式自动切换

### 组件样式
- 圆角统一使用 `BorderRadius.circular(14)` 或 `.circular(16)`
- 间距使用 `SizedBox(height: 16)` 等固定值
- 阴影使用 `BoxShadow` 硬编码，无统一 token

---

## 🔄 数据同步机制

### Delta Sync 流程
```
1. 客户端收集 updatedAt > lastSyncTime 的变更数据
2. POST 到 /api/sync，附带 deviceId 和 lastSyncTime
3. 服务器合并数据 (LWW 策略)，返回服务器端变更
4. 客户端合并服务器数据，更新 lastSyncTime
```

### Token 管理
- 登录后存储在 `SharedPreferences` 的 `auth_session_token`
- 通过 `ApiService.setToken()` 设置到内存
- 每次请求通过 `_getHeaders()` 自动添加 `Authorization: Bearer {token}`
- Token 失效时弹出重新登录对话框

---

## ⚠️ 技术债务与注意事项

1. **SSL 绕过**：`MyHttpOverrides` 全局绕过证书验证，生产环境需移除
2. **无正式状态管理**：复杂状态依赖 `setState` + 回调链，大型重构可考虑 Provider/Riverpod
3. **硬编码颜色值**：部分颜色直接写死在组件中，未完全 Design Token 化
4. **平台分支代码**：多处 `Platform.isAndroid/isWindows` 条件判断，可抽象为平台服务
5. **数据迁移逻辑**：`login_screen.dart` 中包含遗留数据迁移代码，已独立为 MigrationService

---

## 🚀 快速上手指南

### 环境要求
- Flutter SDK >=3.1.0
- Dart SDK >=3.1.0

### 运行命令
```bash
flutter pub get          # 安装依赖
flutter run              # 运行 (默认设备)
flutter run -d windows   # Windows 桌面端
flutter build apk        # 构建 Android APK
```

### 后端配置
- Alibaba Cloud 是新后端能力的优先目标，调试实现位于 `aliyun_debug/`。
- Cloudflare Worker 位于 `math-quiz-backend/`，保留兼容行为。
- Web 通过 Cloudflare Zero Trust API 访问；Windows/Android 可直接访问 Alibaba Cloud HTTP 服务。
- 不要修改 `aliyun_release/`，除非任务明确要求。

---

## 📝 代码风格

- 遵循 `analysis_options.yaml` 中的 lint 规则
- 使用 `flutter_lints` 推荐规则
- 文件命名：`snake_case.dart`
- 类命名：`PascalCase`
- 私有成员：`_camelCase`
- 异步方法：返回 `Future<T>`

---

*最后更新：2026-05-24*
*文档版本：v2.2*
*项目版本：v4.12.19*

