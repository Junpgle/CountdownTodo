# Mac 平台支持

实现版本：v4.14.x
最后更新：2026-06-14

## 概述

macOS（Apple Silicon）平台支持，包括菜单栏集成、桌面小组件、菜单栏专注计时显示、开机自启、自动检查更新等原生体验适配。

## 功能清单

| 功能 | 实现方式 | 版本 |
|------|----------|------|
| 系统菜单栏（文件/查看/窗口/帮助） | `PlatformMenuBar` | v4.14.x |
| 菜单栏专注计时显示（🍅 状态） | `NSStatusItem` + MethodChannel | v4.14.x |
| 桌面小组件（5 种） | WidgetKit + SwiftUI | v4.14.x |
| 开机自启 | `LaunchAtLogin` Swift Package | v4.15 |
| 自动检查更新 | 跨平台 `UpdateService` + `.zip` 下载 | v4.15 |
| 系统托盘 | 跨平台 `window_service.dart` | v4.14.x |
| 窗口管理（保存/恢复位置、全屏） | `window_manager` | v4.14.x |
| Deep Linking（`countdowntodo://`） | `AppDelegate.swift` URL Scheme | v4.14.x |
| 原生关闭对话框 | `MainFlutterWindow.swift` | v4.14.x |

## 详细实现

### 系统菜单栏

**文件**: `lib/widgets/macos_menu_bar.dart`

使用 Flutter 的 `PlatformMenuBar` 提供原生系统菜单：
- **CountDownTodo**: 关于、隐藏
- **文件**: 新建待办 (Cmd+N)、新建倒数日 (Cmd+Shift+N)
- **查看**: 同步、刷新 (Cmd+R)、深色/浅色/系统主题
- **窗口**: 显示主窗口、隐藏 (Cmd+W)、最小化 (Cmd+M)、居中、全屏 (Cmd+Ctrl+F)
- **帮助**: 使用指南、检查更新、GitHub 项目页、关于

在 `main.dart` 中包裹 `MaterialApp`：
```dart
return MacosMenuBar(child: MaterialApp(...));
```

### 菜单栏专注计时

**Native**: `macos/Runner/MacPomodoroStatusBarController.swift`
**Dart**: `lib/services/macos_pomodoro_status_bar_service.dart`

- 单例 `NSStatusItem`，显示番茄钟状态
- 显示格式：
  - `🍅 X分` — 专注中（正计时/倒计时）
  - `⏸ X分` — 已暂停
  - `☕ X分` — 休息中
- 菜单项：显示主窗口、暂停/继续、停止专注、退出
- 远端专注（跨设备同步）显示"远端专注"前缀，隐藏暂停/停止按钮
- 通过 MethodChannel `countdown_todo/macos_status_bar` 同步状态
- 监听本地 `PomodoroService.onRunStateChanged` 和远端 `PomodoroSyncService.instance.onStateChanged`

### 桌面小组件

**Native**: `macos/CountDownTodoWidgetExtension/`
**Dart**: `lib/services/widget_service.dart`

5 种 WidgetKit 小组件：

| 组件 | 尺寸 | 内容 |
|------|------|------|
| Today Overview | 小/中/大 | 总览（倒计时、待办、课程、专注） |
| 倒数日 (Countdown) | 小/中 | 最近的重要日倒计时 |
| 今日待办 (Todo) | 小/中 | 今日待办列表 |
| 今日课程 (Course) | 小/中 | 今日课表 |
| 专注 (Focus) | 小/中 | 番茄钟专注计时状态 |

数据同步：
- Dart 端构建 `WidgetSnapshot` 数据模型
- 通过 MethodChannel `com.countdowntodo/widget` 写入 `UserDefaults(suiteName:)` + 文件缓存
- 调用 `WidgetCenter.shared.reloadAllTimelines()` 刷新
- App Group: `group.com.junpgle.countdowntodo`

### 开机自启

**Native**: `MainFlutterWindow.swift` — MethodChannel `launch_at_startup`
**Dart**: `window_service.dart` — `launch_at_startup` 包

- 通过 `LaunchAtLogin` Swift Package 获取/设置状态
- 系统托盘菜单可选"开机启动"
- Dart 端通过 `launchAtStartup.isEnabled()` / `.enable()` / `.disable()` 控制

### 检查更新

跨平台 `UpdateService` 统一处理：
- 更新文件命名：`CountdownTodo_v{version}.zip`
- 设备架构标识：`macos`
- 下载 URL 取自 manifest 的 `macPackageUrl`
- 安装方式：下载 .zip 后打开 Finder，用户手动解压拖入 Applications
- 菜单栏"检查更新"入口

## 平台守卫

所有 Mac 特定代码使用 `Platform.isMacOS` 守卫：

```dart
if (Platform.isMacOS) {
  // Mac-only code
}
```

涉及文件：`main.dart`, `window_service.dart`, `widget_service.dart`, `macos_pomodoro_status_bar_service.dart`, `update_service.dart`, `notification_service.dart`, `storage_service.dart` 等 14 个文件。

## 构建配置

- `macos/Runner/Configs/AppInfo.xcconfig`
  - `PRODUCT_BUNDLE_IDENTIFIER = com.mathquiz.junpgle.com.mathQuizApp`
  - `ARCHS = arm64`（仅 Apple Silicon）
- 授权文件：App Sandbox 启用，App Group 共享
- 小组件扩展独立授权文件

## 相关文件

- `lib/widgets/macos_menu_bar.dart` — 系统菜单栏
- `lib/services/macos_pomodoro_status_bar_service.dart` — 菜单栏专注状态服务
- `lib/services/widget_service.dart` — 桌面小组件数据同步
- `lib/services/window_service.dart` — 窗口管理 + 开机自启
- `lib/services/update_service.dart` — 更新检查与安装
- `macos/Runner/MacPomodoroStatusBarController.swift` — 原生菜单栏控制器
- `macos/Runner/MainFlutterWindow.swift` — 原生窗口、开机自启、小组件桥梁
- `macos/CountDownTodoWidgetExtension/` — 小组件扩展
