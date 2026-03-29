# 灵动岛模块 - 扩展开发指南

本文档为扩展 Windows 灵动岛模块提供指南，包括新功能、状态和行为的添加方法。

## 架构概览

### 模块结构

```
lib/windows_island/
├── island_config.dart        # 集中管理的常量和配置
├── island_channel.dart       # 与主应用的 IPC 通信
├── island_debug.dart         # 调试/测试页面
├── island_entry.dart         # 窗口入口点 (islandMain)
├── island_manager.dart       # 窗口生命周期管理
├── island_payload.dart       # 数据传输对象
├── island_reminder.dart      # 提醒服务
├── island_state_handler.dart # 可扩展的状态管理
├── island_ui.dart            # UI 组件和状态机
└── island_win32.dart         # Win32 API 工具函数
```

### 服务层结构

```
lib/services/
├── clipboard_service.dart    # 剪贴板监听服务
├── float_window_service.dart # 悬浮窗/岛集成服务
├── island_data_provider.dart # 岛数据聚合中心（含缓存）
├── island_slot_provider.dart # 槽位数据获取
└── snooze_dialog.dart        # 稍后提醒对话框
```

### 数据流

```
HomeDashboard
  └── FloatWindowService.update()
        └── IslandDataProvider.buildPayload()
              ├── 缓存的 style/priority/theme
              ├── 缓存的 slot data (30秒有效)
              └── IslandManager.sendStructuredPayload()
                    └── Island Window (island_entry.dart)
                          └── IslandUI (状态机 + 渲染)
```

## 核心概念

### 1. 状态 (States)

灵动岛通过有限状态机运行。每个状态定义：
- 窗口尺寸
- UI 内容
- 状态转换规则

**内置状态：**

| 状态 | 说明 | 尺寸 |
|------|------|------|
| `idle` | 默认时钟显示 | 120x34 |
| `focusing` | 专注计时中 | 100x46 |
| `hoverWide` | 鼠标悬停展开 | 380x46 |
| `splitAlert` | 分屏通知 | 300x36 |
| `stackedCard` | 详细卡片视图 | 280x140 |
| `reminderPopup` | 提醒弹窗 | 320x150/180 |
| `reminderSplit` | 双胶囊提醒 | 480x46 或 320x300+ |
| `reminderCapsule` | 单胶囊提醒 | 160x46 |
| `copiedLink` | 复制链接通知 | 340x46 |

### 2. 数据载荷 (Payload)

数据通过 `Map<String, dynamic>` 格式传递到灵动岛：

```dart
{
  'state': 'focusing',           // 目标状态
  'focusData': {
    'title': '任务名称',
    'endMs': 1234567890,         // 结束时间戳 (毫秒)
    'timeLabel': '25:00',        // 时间显示
    'isCountdown': true,         // 是否倒计时
    'tags': ['学习', '数学'],    // 标签
    'syncMode': 'local',         // 同步模式
  },
  'reminderPopupData': {
    'type': 'todo',              // 类型: 'todo' 或 'course'
    'title': '会议',
    'subtitle': '301会议室',
    'startTime': '14:00',
    'endTime': '15:00',
    'minutesUntil': 15,          // 距开始/结束的分钟数
    'isEnding': false,           // 是否是结束提醒
    'itemId': 'unique-id',       // 唯一标识
  },
  'copiedLinkData': {
    'url': 'https://example.com',
    'displayUrl': 'example.com', // 显示用的简化 URL
  },
}
```

### 3. 操作 (Actions)

用户交互会触发操作，发送回主应用：

| 操作 | 说明 | 数据 |
|------|------|------|
| `finish` | 专注完成 | remainingSecs |
| `abandon` | 放弃专注 | 0 |
| `reminder_ok` | 确认提醒 | - |
| `remind_later` | 稍后提醒 | - |
| `open_link` | 打开链接 | url |
| `check_reminder` | 强制检查提醒 | - |
| `snooze_reminder` | 延迟提醒 | snoozeMinutes |

## 扩展点

### 添加自定义状态

**步骤 1：在 `island_config.dart` 中定义状态**

```dart
enum IslandStateConfig {
  // ... 现有状态
  myCustomState,  // 新增状态
}
```

**步骤 2：在 `IslandConfig.sizeForState()` 中添加尺寸配置**

```dart
case IslandStateConfig.myCustomState:
  return const Size(200, 100);
```

**步骤 3：创建状态处理器（可选）**

```dart
class MyCustomHandler extends IslandStateHandler {
  @override
  String get stateId => 'my_custom_state';

  @override
  IslandStateConfig get configState => IslandStateConfig.myCustomState;

  @override
  Widget build(
    BuildContext context,
    Map<String, dynamic>? payload,
    IslandStateContext stateContext,
  ) {
    return Container(
      color: Colors.blue,
      child: Text('自定义状态'),
    );
  }
}
```

**步骤 4：注册处理器**

```dart
IslandStateRegistry.register(MyCustomHandler());
```

### 修改时间常量

所有时间值集中在 `island_config.dart` 中：

```dart
class IslandConfig {
  // 鼠标悬停行为
  static const Duration hoverEnterDelay = Duration(milliseconds: 100);
  static const Duration hoverExitDelay = Duration(milliseconds: 120);
  static const Duration hoverMinStay = Duration(milliseconds: 400);

  // 状态切换
  static const Duration transitionDuration = Duration(milliseconds: 200);
  static const int transitionDebounceMs = 200;

  // 提醒相关
  static const Duration reminderCheckInterval = Duration(seconds: 10);
  static const Duration copiedLinkDismissDuration = Duration(seconds: 10);
}
```

### 自定义颜色

```dart
class IslandConfig {
  static const Color successColor = Color(0xFF4CAF50);   // 成功绿
  static const Color dangerColor = Color(0xFFD32F2F);    // 危险红
  static const Color warningColor = Color(0xFFFF9800);   // 警告橙
  static const Color focusColor = Color(0xFF6366F1);     // 专注紫
  static const Color bgColor = Color(0xFF1C1C1E);        // 背景色
}
```

### 添加提醒类型

在 `island_reminder.dart` 中扩展提醒检查逻辑：

```dart
/// 检查自定义提醒源
static Future<List<Map<String, dynamic>>> _checkCustomReminders(
  DateTime now,
) async {
  final reminders = <Map<String, dynamic>>[];

  // 你的自定义提醒数据源
  final items = await getCustomReminders();
  for (final item in items) {
    final diff = item.startTime.difference(now).inMinutes;
    if (diff >= 0 && diff <= 20) {
      reminders.add({
        'type': 'custom',
        'title': item.title,
        'subtitle': item.description,
        'minutesUntil': diff,
        'isEnding': false,
        'itemId': item.id,
      });
    }
  }

  return reminders;
}
```

然后在 `checkUpcomingReminder()` 中调用：

```dart
final customReminders = await _checkCustomReminders(now);
allReminders.addAll(customReminders);
```

### Win32 工具函数

使用 `island_win32.dart` 进行窗口操作：

```dart
import 'island_win32.dart';

// 获取窗口句柄
final hwnd = getSmallestFlutterWindow();

// 调整窗口大小
resizeCurrentWindow(200, 100);

// 移动窗口
moveCurrentWindow(100, 200);

// 获取当前位置
final rect = getWindowRect();

// 开始拖动
startWindowDragging();

// 获取 DPI 缩放比例
final scale = getIslandScaleFactor(hwnd);
```

## IPC 通信

### 发送数据到灵动岛

从主应用使用 `IslandManager`：

```dart
final manager = IslandManager();
await manager.createIsland('island-1');

// 发送数据载荷
await manager.sendStructuredPayload('island-1', {
  'state': 'focusing',
  'focusData': {
    'title': '学习时间',
    'endMs': DateTime.now().add(Duration(minutes: 25)).millisecondsSinceEpoch,
  },
});
```

### 接收操作

操作通过 `island_action.json` 文件写入，由 `IslandChannel` 读取：

```dart
IslandChannel.actionStream.listen((event) {
  final action = event['action'];
  final windowId = event['windowId'];

  switch (action) {
    case 'finish':
      // 处理专注完成
      break;
    case 'reminder_ok':
      // 处理提醒确认
      break;
  }
});
```

## 数据缓存机制

### IslandDataProvider 缓存

`IslandDataProvider` 提供智能缓存，减少重复计算：

| 数据类型 | 缓存时长 | 失效方法 |
|----------|---------|---------|
| 槽位数据 (todos/courses) | 30秒 | `invalidateSlotCache()` |
| Style 设置 | 5分钟 | `invalidateCache()` |
| Priority 列表 | 5分钟 | `invalidateCache()` |
| Theme | 5分钟 | `invalidateCache()` |

**使用示例：**

```dart
import '../services/float_window_service.dart';

// 数据变更时刷新槽位缓存
FloatWindowService.invalidateSlotCache();

// 完全重置缓存
FloatWindowService.invalidateCache();

// 获取调试信息
final debugInfo = FloatWindowService.getDebugInfo();
```

### 变化检测

当以下条件满足时，更新会被跳过：
- `_lastSentEndMs` 未变化
- `_lastSentState` 未变化
- 非强制更新 (`forceReset = false`)

## 最佳实践

1. **使用常量**：始终使用 `IslandConfig` 管理时间、颜色和尺寸
2. **状态保护**：切换状态前检查当前状态，防止循环切换
3. **防抖处理**：用户交互使用适当的防抖延迟
4. **内存清理**：在 `dispose()` 中取消所有定时器
5. **错误处理**：异步操作用 try-catch 包裹
6. **测试调试**：使用 `IslandDebugPage` 测试 UI 状态

## 调试模式

使用调试页面测试状态，无需完整 IPC：

```dart
import 'package:math_quiz_app/windows_island/island_debug.dart';

// 在应用中
Navigator.push(context, MaterialPageRoute(
  builder: (_) => IslandDebugPage(),
));
```

## 问题排查

| 问题 | 解决方案 |
|------|----------|
| 窗口不透明 | 检查 `initFfiTransparent()` 中的 Win32 初始化 |
| 状态不更新 | 验证 payload 格式是否符合预期结构 |
| 定时器泄漏 | 确保 `dispose()` 取消了所有定时器 |
| IPC 不工作 | 检查 `island_action.json` 的权限和路径 |
| 槽位数据不更新 | 调用 `FloatWindowService.invalidateSlotCache()` |
| 性能问题 | 检查缓存是否生效，使用 `getDebugInfo()` |

## 文件参考

| 文件 | 用途 | 行数 |
|------|------|------|
| `island_config.dart` | 常量和配置 | ~170 |
| `island_win32.dart` | Win32 API 封装 | ~280 |
| `island_reminder.dart` | 提醒服务 | ~200 |
| `island_state_handler.dart` | 状态注册器 | ~150 |
| `island_payload.dart` | 数据模型 | ~130 |
| `island_entry.dart` | 入口点 | ~350 |
| `island_ui.dart` | UI 组件 | ~1000 |
| `island_manager.dart` | 窗口管理器 | ~330 |
| `island_channel.dart` | IPC 通道 | ~260 |
| `island_data_provider.dart` | 数据聚合中心 | ~250 |
| `island_slot_provider.dart` | 槽位数据提供 | ~200 |
| `clipboard_service.dart` | 剪贴板服务 | ~140 |
| `float_window_service.dart` | 悬浮窗服务 | ~400 |
| `snooze_dialog.dart` | 稍后提醒对话框 | ~90 |
