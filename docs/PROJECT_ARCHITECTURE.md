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

---

## 🛠 技术栈概览

| 类别 | 技术 | 说明 |
|------|------|------|
| **框架** | Flutter 3.x | 跨平台 UI 框架 |
| **语言** | Dart (SDK >=3.1.0 <4.0.0) | 空安全 |
| **UI 库** | Material Design 3 | `useMaterial3: true` |
| **状态管理** | ValueListenable + setState + Stream | 无第三方状态管理库 |
| **本地存储** | SharedPreferences | JSON 序列化存储 |
| **网络请求** | http 包 | 封装在 `ApiService` |
| **后端** | Cloudflare Workers + D1 | 或阿里云 ECS |
| **同步协议** | Delta Sync (增量同步) | LWW (Last Write Wins) 策略 |
| **实时通信** | WebSocket | 番茄钟跨端感知 |
| **桌面窗口** | desktop_multi_window + window_manager | 灵动岛独立进程 |

### 关键依赖项
```yaml
# 核心
http: ^1.2.0              # HTTP 客户端
shared_preferences: ^2.2.0 # 本地持久化
web_socket_channel: ^3.0.1 # WebSocket 通信
uuid: ^4.2.2               # 全局唯一 ID 生成
cached_network_image: ^3.3.0 # 图片缓存
intl: ^0.20.2              # 国际化 & 时间格式化

# 通知 & 权限
flutter_local_notifications: ^20.0.0 # 本地通知
permission_handler: ^12.0.1          # 权限管理
device_info_plus: ^11.1.0            # 设备信息

# 桌面端
window_manager: ^0.3.8     # 桌面窗口管理
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

```
lib/
├── main.dart                 # 应用入口，路由配置，主题管理，灵动岛分流
├── models.dart               # 核心数据模型 (Question, TodoItem, CountdownItem, TimeLogItem)
├── models/
│   └── chat_message.dart     # 聊天消息模型
├── storage_service.dart      # 本地存储服务 (用户系统 + 增量同步 + 屏幕时间)
├── update_service.dart       # 应用更新服务 (版本检查 + 下载管理)
├── utils/
│   └── page_transitions.dart # 页面转场动画
│
├── screens/                  # 页面组件 (27 文件)
│   ├── splash_screen.dart    # 启动页
│   ├── login_screen.dart     # 登录/注册页
│   ├── home_dashboard.dart   # 主仪表盘 (首页)
│   ├── pomodoro_screen.dart  # 番茄钟页面
│   ├── quiz_screen.dart      # 数学测验页
│   ├── todo_chat_screen.dart # 待办聊天
│   ├── todo_confirm_screen.dart # 待办确认页
│   ├── add_todo_screen.dart  # 添加待办
│   ├── time_log_screen.dart  # 时间日志
│   ├── screen_time_detail_screen.dart # 屏幕时间详情
│   ├── historical_todos_screen.dart   # 历史待办
│   ├── historical_countdowns_screen.dart # 历史倒计时
│   ├── course_screens.dart   # 课程管理
│   ├── band_sync_screen.dart # 手环同步
│   ├── feature_guide_screen.dart # 功能引导
│   ├── settings_screen.dart  # 设置入口
│   ├── about_screen.dart     # 关于页面
│   ├── home_settings_screen.dart # 首页设置
│   ├── math_menu_screen.dart # 数学菜单
│   ├── other_screens.dart    # 其他页面
│   ├── animation_settings_page.dart # 动画设置
│   ├── pomodoro/             # 番茄钟子模块
│   │   ├── pomodoro_utils.dart
│   │   ├── views/
│   │   │   ├── workbench_view.dart
│   │   │   └── stats_view.dart
│   │   └── widgets/
│   │       ├── workbench_task_area.dart
│   │       ├── workbench_actions.dart
│   │       ├── tag_manager_sheet.dart
│   │       ├── immersive_timer.dart
│   │       └── fading_indexed_stack.dart
│   └── settings/             # 设置子模块
│       ├── widgets/          # 设置专用组件 (8 文件)
│       ├── handlers/         # 设置事件处理 (3 文件)
│       ├── dialogs/          # 设置弹窗 (6 文件)
│       ├── server_choice_page.dart
│       ├── notification_settings_page.dart
│       ├── llm_config_page.dart
│       └── device_version_detail_page.dart
│
├── services/                 # 业务服务层 (28 文件)
│   ├── api_service.dart      # API 请求封装 (核心)
│   ├── pomodoro_service.dart # 番茄钟业务逻辑
│   ├── pomodoro_sync_service.dart # 番茄钟 WebSocket 同步
│   ├── llm_service.dart      # 大模型智能解析
│   ├── course_service.dart   # 课表统一管理
│   ├── screen_time_service.dart # 屏幕时间服务
│   ├── notification_service.dart # 通知服务
│   ├── reminder_schedule_service.dart # 定时提醒调度
│   ├── migration_service.dart # 数据迁移
│   ├── band_sync_service.dart # 手环同步
│   ├── tai_service.dart      # Windows TAI 采集
│   ├── float_window_service.dart # 悬浮窗服务
│   ├── window_service.dart   # 窗口生命周期
│   ├── widget_service.dart   # Android 小组件
│   ├── system_control_service.dart # 系统控制
│   ├── splash_service.dart   # 启动服务
│   ├── chat_storage_service.dart # 聊天存储
│   ├── todo_parser_service.dart # 待办解析
│   ├── external_share_handler.dart # 外部分享处理
│   ├── clipboard_service.dart # 剪贴板
│   ├── animation_config_service.dart # 动画配置
│   ├── island_data_provider.dart # 灵动岛数据源
│   ├── island_slot_provider.dart # 灵动岛插槽
│   ├── snooze_dialog.dart    # 稍后提醒弹窗
│   ├── hfut_schedule_parser.dart   # 合肥工业大学
│   ├── xmu_schedule_parser.dart    # 厦门大学
│   ├── xidian_schedule_parser.dart # 西安电子科技大学
│   └── zfsoft_schedule_parser.dart # 正方教务通用
│
├── widgets/                  # 可复用 UI 组件 (6 文件)
│   ├── home_app_bar.dart     # 首页 AppBar
│   ├── home_sections.dart    # 通用板块组件
│   ├── todo_section_widget.dart # 待办区块
│   ├── countdown_section_widget.dart # 倒计时区块
│   ├── course_section_widget.dart # 课表区块
│   └── pomodoro_today_section.dart # 今日番茄区块
│
└── windows_island/           # Windows 灵动岛模块 (12 文件)
    ├── island_entry.dart     # 独立窗口入口
    ├── island_manager.dart   # 窗口生命周期管理
    ├── island_ui.dart         # UI 渲染核心
    ├── island_state_stack.dart # 栈式状态管理
    ├── island_state_handler.dart # 状态变更处理
    ├── island_payload.dart   # 数据传输对象
    ├── island_channel.dart   # IPC 通信
    ├── island_config.dart    # 配置常量
    ├── island_reminder.dart  # 提醒服务
    ├── island_debug.dart     # 调试页面
    └── island_win32.dart     # Win32 API 封装
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
// 使用 StorageService 统一管理
await StorageService.saveTodos(username, items);  // 保存
final items = await StorageService.getTodos(username);  // 读取

// 存储格式：SharedPreferences 存储 JSON 字符串列表
// Key 格式："{功能}_{用户名}" 例如 "user_todos_john"
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
- 默认服务器：`https://mathquiz.junpgle.me` (Cloudflare)
- 备用服务器：`http://101.200.13.100:8082` (阿里云)
- 用户可在登录页切换服务器

---

## 📝 代码风格

- 遵循 `analysis_options.yaml` 中的 lint 规则
- 使用 `flutter_lints` 推荐规则
- 文件命名：`snake_case.dart`
- 类命名：`PascalCase`
- 私有成员：`_camelCase`
- 异步方法：返回 `Future<T>`

---

*最后更新：2026-04-05*
*文档版本：v2.0*
*项目版本：v3.0.8*
