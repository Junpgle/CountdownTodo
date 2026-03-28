# 项目架构文档 - CountDownTodo

## 📌 项目概述

**CountDownTodo** 是一个跨平台效率工具应用，核心功能包括：
- 待办事项 (Todo) 管理
- 重要日倒计时 (Countdown)
- 番茄钟 (Pomodoro) 专注计时
- 数学测验 (Math Quiz)
- 屏幕使用时间统计 (Screen Time)
- 课表管理 (Course Schedule)
- 多端数据同步 (Cloud Sync)

---

## 🛠 技术栈概览

| 类别 | 技术 | 说明 |
|------|------|------|
| **框架** | Flutter 3.x | 跨平台 UI 框架 |
| **语言** | Dart (SDK >=3.1.0 <4.0.0) | 空安全 |
| **UI 库** | Material Design 3 | `useMaterial3: true` |
| **状态管理** | ValueListenable + setState | 无第三方状态管理库 |
| **本地存储** | SharedPreferences | JSON 序列化存储 |
| **网络请求** | http 包 | 封装在 `ApiService` |
| **后端** | Cloudflare Workers + D1 | 或阿里云 ECS |
| **同步协议** | Delta Sync (增量同步) | LWW (Last Write Wins) 策略 |
| **实时通信** | WebSocket | 番茄钟跨端感知 |

### 关键依赖项
```yaml
http: ^1.2.0              # HTTP 客户端
shared_preferences: ^2.2.0 # 本地持久化
web_socket_channel: ^3.0.1 # WebSocket 通信
uuid: ^4.2.2               # 全局唯一 ID 生成
cached_network_image: ^3.3.0 # 图片缓存
flutter_local_notifications: ^20.0.0 # 本地通知
window_manager: ^0.3.8     # 桌面窗口管理
desktop_multi_window: ^0.3.0 # 多窗口支持
```

---

## 📂 目录结构说明

```
lib/
├── main.dart                 # 应用入口，路由配置，主题管理
├── models.dart               # 核心数据模型 (TodoItem, CountdownItem, TimeLogItem)
├── storage_service.dart      # 本地存储服务 (SharedPreferences 封装)
├── update_service.dart       # 应用更新服务
│
├── screens/                  # 页面组件
│   ├── login_screen.dart     # 登录/注册页
│   ├── home_dashboard.dart   # 主仪表盘 (首页)
│   ├── pomodoro_screen.dart  # 番茄钟页面
│   ├── quiz_screen.dart      # 数学测验页
│   ├── settings_screen.dart  # 设置页面
│   ├── pomodoro/             # 番茄钟子页面
│   └── settings/             # 设置子页面
│
├── services/                 # 业务服务层
│   ├── api_service.dart      # API 请求封装 (核心)
│   ├── pomodoro_service.dart # 番茄钟业务逻辑
│   ├── pomodoro_sync_service.dart # 番茄钟 WebSocket 同步
│   ├── screen_time_service.dart # 屏幕时间服务
│   ├── course_service.dart   # 课表服务
│   ├── notification_service.dart # 通知服务
│   ├── float_window_service.dart # 悬浮窗服务
│   └── *_schedule_parser.dart # 各校课表解析器
│
├── widgets/                  # 可复用 UI 组件
│   ├── home_app_bar.dart     # 首页 AppBar
│   ├── home_sections.dart    # 首页通用区块组件
│   ├── todo_section_widget.dart # 待办区块
│   ├── countdown_section_widget.dart # 倒计时区块
│   ├── course_section_widget.dart # 课表区块
│   └── pomodoro_today_section.dart # 今日番茄区块
│
└── windows_island/           # Windows 灵动岛功能
    ├── island_entry.dart
    ├── island_manager.dart
    └── island_ui.dart
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
5. **数据迁移逻辑**：`login_screen.dart` 中包含遗留数据迁移代码，可独立为 MigrationService

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

*最后更新：2025-01-XX*
*文档版本：v1.0*