# windows_island/ — Windows 灵动岛模块

## 目录定位

平台特定模块（Platform-specific Module），为 Windows 桌面端实现类似 macOS Dynamic Island 的悬浮窗组件。通过 `desktop_multi_window` 插件在独立 Flutter 引擎中运行，与主窗口进程隔离。

---

## 文件索引

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `island_entry.dart` | 独立窗口入口点 | `islandMain()` |
| `island_manager.dart` | 窗口生命周期管理（单例） | `IslandManager` |
| `island_ui.dart` | 灵动岛 UI 渲染 | `IslandUI` |
| `island_state_stack.dart` | 栈式状态管理器 | `IslandStateStack`, `IslandState` |
| `island_state_handler.dart` | 状态变更处理器 | 状态转换逻辑 |
| `island_payload.dart` | 数据传输对象 | `IslandPayload` |
| `island_channel.dart` | 主窗口 ↔ 子窗口 IPC 通信 | `IslandChannel` |
| `island_config.dart` | 模块配置常量 | `IslandConfig` |
| `island_win32.dart` | Win32 API 封装 | 窗口透明、置顶、穿透 |
| `island_reminder.dart` | 提醒服务 | `IslandReminderService` |
| `island_debug.dart` | 调试页面 | `IslandDebugPage` |

---

## 核心逻辑摘要

### 架构概述

```
主窗口进程 (Main Flutter Engine)
  │
  ├── IslandManager.createIsland()
  │     └── desktop_multi_window 创建独立窗口
  │
  └── IslandChannel (IPC 通信)
        ├── File IPC: 基于 JSON 文件轮询 (200ms)
        └── MethodChannel: 备用通信通道

独立窗口进程 (Island Flutter Engine)
  │
  ├── islandMain() 入口
  ├── IslandUI (UI 渲染)
  └── IslandStateStack (状态管理)
```

### island_entry.dart

独立窗口入口点，被 `main.dart` 的 `multi_window` 参数路由调用：

```dart
// main.dart 中的检测逻辑
if (args.isNotEmpty && args[0] == 'multi_window') {
  await island_entry.islandMain(args);
  return;
}
```

**职责：**
1. 初始化 Win32 窗口属性（透明、置顶、无任务栏）
2. 恢复上次窗口位置（从 `StorageService.getIslandBounds`）
3. 设置 IPC 轮询监听主窗口指令
4. 启动 `IslandUI` Widget

### island_manager.dart

单例模式管理灵动岛窗口生命周期：

```dart
IslandManager().createIsland('island-1');  // 创建窗口
IslandManager().sendPayload('island-1', payload);  // 发送数据
IslandManager().destroyIsland('island-1');  // 销毁窗口
```

**核心机制：**
- **孤儿窗口清理**：启动时检测并销毁上次会话残留的窗口
- **窗口 ID 持久化**：文件存储 `island_wid_$islandId.txt`
- **并发创建保护**：`_creating` Map 防止重复创建

### island_state_stack.dart

栈式状态管理，确保 UI 状态可预测、可恢复：

```dart
enum IslandState {
  idle,              // 空闲（时钟胶囊）
  focusing,          // 专注中
  hoverWide,         // 悬停展开
  stackedCard,       // 堆叠卡片
  splitAlert,        // 分裂提醒
  finishConfirm,     // 完成确认
  abandonConfirm,    // 放弃确认
  finishFinal,       // 完成最终
  reminderPopup,     // 弹窗提醒
  reminderSplit,     // 双胶囊提醒
  reminderCapsule,   // 单胶囊提醒
  copiedLink,        // 复制链接
  quickControls,     // 快速控制面板
  musicPlayer,       // 音乐播放器
}
```

**栈操作：**
```dart
push(state)       // 入栈临时状态（confirm / hover）
pop(state)        // 出栈恢复下层
replaceTop(state) // 替换栈顶
replaceBase(state)// 替换栈底（idle ↔ focusing）
clearToIdle()     // 清空回 idle
```

**受保护状态：**
```dart
// 外部 payload 无法覆盖这些状态
static const protectedStates = {
  IslandState.finishConfirm,
  IslandState.abandonConfirm,
  IslandState.finishFinal,
  IslandState.copiedLink,
  IslandState.reminderPopup,
};
```

### island_payload.dart

数据传输对象，定义主窗口 → 子窗口的数据结构：

```dart
class IslandPayload {
  final int endMs;           // 倒计时结束时间
  final String title;        // 任务标题
  final List<String> tags;   // 标签列表
  final bool isLocal;        // 是否本地专注
  final int mode;            // 显示模式
  final int style;           // 样式
  final String left, right;  // 左右插槽内容
  final List<Map<String, String>> reminderQueue; // 提醒队列
  // ...
}
```

### island_channel.dart

主窗口 ↔ 子窗口 IPC 通信层：

**File IPC 机制（核心）：**
```
主窗口写入 → island_action.json → 子窗口轮询读取 → 处理指令
子窗口写入 → island_action.json → 主窗口轮询读取 → 处理响应
```

**原因**：Flutter 的 `desktop_multi_window` 在不同引擎间 MethodChannel 不可靠，文件 IPC 更稳定。

**Ready 信号：**
```dart
// 等待子窗口就绪
await IslandChannel.waitForReady(windowId, timeout: Duration(seconds: 2));
```

### island_ui.dart

灵动岛 UI 核心，包含：

1. **状态驱动渲染**：根据 `IslandStateStack.current` 切换 UI 形态
2. **动画系统**：
   - `_splitController`：分裂动画
   - `_sizeController`：尺寸过渡
   - `_pulseController`：强提醒脉冲
3. **卡片轮播**：支持滚轮切换不同信息卡片
4. **系统控制**：音量、亮度、音乐播放器控制面板
5. **倒计时/正计时**：实时时间显示

**UI 形态：**
```
idle (胶囊态)
  ↓ hover
hoverWide (展开态)
  ↓ 点击
stackedCard (卡片态)
  ↓ 滚轮
cardCarousel (轮播态)

focusing (专注态)
  ↓ 提醒
reminderSplit (分裂提醒)
  ↓ 确认
finishConfirm → finishFinal → idle
```

---

## 调用链路

```
main.dart
  └── IslandManager.createIsland()
        ├── IslandChannel.createWindow()
        └── 发送初始 payload

HomeDashboard / PomodoroScreen
  └── IslandManager.sendPayload()
        └── 通过 File IPC 写入 island_action.json

IslandUI (独立进程)
  ├── 读取 island_action.json
  ├── IslandStateStack 状态转换
  └── 渲染对应 UI 形态
```

---

## 外部依赖

- `desktop_multi_window`：多窗口管理
- `window_manager`：窗口属性控制
- `win32`：Win32 API FFI 调用
- `ffi`：Dart FFI 基础库
- `path_provider`：应用目录路径
- `url_launcher`：URL 打开

---

## 扩展指南

模块扩展指南详见 [EXTENDING.md](./EXTENDING.md)，包含：
- 添加新 UI 形态的步骤
- 自定义 payload 字段
- 状态栈操作规范
- 调试技巧

---

*最后更新：2026-04-13*
