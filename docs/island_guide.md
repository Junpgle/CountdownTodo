# 灵动岛 (Island) 开发说明

本文档面向后续维护者，解释本仓库中“灵动岛 / Island”功能的设计、实现要点、IPC 协议、关键文件位置、常见问题及扩展建议。

---

## 目录

- 概览
- 关键文件与类
- Payload 规范（结构化与 legacy）
- 主进程 -> 子窗口（完整流程）
- 子窗口的 Windows 原生处理要点
- IslandChannel 与消息可靠性
- 常见操作示例（代码片段）
- 错误处理、重试与防抖
- 调试建议与常见问题
- 扩展建议与向后兼容
- 快速参考（方法签名）

---

## 1. 概览

“灵动岛”（Island）是一个在桌面（主要为 Windows）以独立、轻量、可透明窗口展示的浮动组件，用于显示专注计时、提醒等信息。实现基于 `desktop_multi_window` 插件与主进程/子窗口间的 IPC。主进程负责创建与管理窗口并推送数据，子窗口负责渲染 UI 并将用户操作回传主进程。

设计目标：
- 尽量无边框、透明、始终在最上层且不占任务栏（如果宿主支持）；
- 支持结构化 payload（推荐）与 legacy DTO 的兼容；
- 提供可靠的 ready/handshake，用于减少消息丢失或空白显示；
- 对宿主不支持的功能采取 best-effort（尝试）且做好回退。


## 2. 关键文件与类（位置）

- `lib/windows_island/island_entry.dart`
  - 子窗口入口 `islandMain`。负责 Flutter 绑定、MethodChannel 注册、解析主进程 payload、发送 `ready`，以及将 `IslandUI` 运行在子窗口。
  - 包含 Windows FFI (win32) 实现：查找 HWND、设置无框透明、SetWindowPos、DPI 处理等。

- `lib/windows_island/island_ui.dart`
  - 子窗口 UI 与状态机 (`IslandState` 等)。负责将 payload 映射为视觉状态并处理用户交互（如 `finish` / `abandon`）。

- `lib/windows_island/island_channel.dart`
  - IPC 封装：对 `MethodChannel('mixin.one/desktop_multi_window')` 的高层封装。
  - 提供 `createWindow`、`postMessage`、`setWindowBounds`、`setWindowTransparent`、`showWindow`、`destroyWindow`。
  - 管理 ready 等待队列（`_readyCompleters`、`_anonReadyQueue`、`_readySet`）与 `actionStream`。

- `lib/windows_island/island_manager.dart`
  - 主进程窗口管理单例 `IslandManager`：缓存 windowId、创建窗口、发送 payload、透明支持缓存、持久化初始 bounds。

- `lib/windows_island/island_payload.dart`
  - legacy DTO：`IslandPayload.fromMap` / `toMap()`，包含业务字段（`endMs`, `title`, `tags` 等）。

- `lib/windows_island/payload.dart`
  - 通用消息封装（版本 `v`、`msg_id`、`type`、`timestamp`、`island_id`、`payload`）与 `IslandEvent`。用于需要消息级追踪的场景。

- `lib/services/float_window_service.dart`
  - 决定何时以 Island 风格展示浮窗，构建结构化 payload 并调用 `IslandManager`。

- `lib/storage_service.dart`
  - 用于保存/读取岛位置等持久化数据（例如 `island-1` 的 bounds）。


## 3. Payload 规范

项目支持两类主要 payload：结构化 payload（推荐）与 legacy DTO（兼容）。另外存在一个消息级封装 (`payload.dart`) 可用于追踪。

A. 结构化 Payload（推荐，由主进程构建）
- 示例 (简化)：

```dart
{
  'state': 'focusing',
  'theme': 'system',
  'focusData': {
    'title': '学习',
    'timeLabel': '25:00',
    'isCountdown': true,
    'tags': ['学习'],
    'syncMode': 'local',
  },
  'reminderData': {...},
  'dashboardData': {'leftSlot':'', 'rightSlot':''},
  'transparentSupported': true,
  'legacy': { /* 可选 legacy map */ }
}
```

- 当 `island_entry` 收到包含 `focusData` 或 `state` 的 map 时，会把整个结构化 map 直接交给 UI；若包含 `legacy` 字段则优先用 legacy map。

B. Legacy DTO (`lib/windows_island/island_payload.dart`)
- 扁平字段集合，包括 `endMs, title, tags, isLocal, mode, style, left, right, forceReset, topBarLeft, topBarRight, reminderQueue, detail_*` 等。
- 通过 `IslandPayload.fromMap` 解析输入 map，`toMap` 输出给子窗口使用旧逻辑。

C. Message wrapper (`lib/windows_island/payload.dart`)
- 定义：`v`, `msg_id`, `type`, `timestamp`, `island_id`, `payload`。
- 当需要消息级别的追踪/确认（ACK）时，可以采用此封装并在 `IslandChannel` / `IslandManager` 中实现 msg_id 的追踪与超时重试。


## 4. 主进程 -> 子窗口 完整流程

1. 主进程调用 `IslandManager().createIsland(islandId)`。
   - 检查缓存 `_windowIdCache`。
   - 若已有创建进行中，复用 `_creating` 中的 future 避免重复创建。
   - `_doCreate` 构建 `initialStructured` payload（包含简单 legacy DTO），并调用 `IslandChannel.createWindow(args)`。`args` 常含：`arguments: 'islandMain'`, `hiddenAtLaunch`, `alwaysOnTop`, `skipTaskbar`, `transparent`, `payload`, `initialBounds` 等。
   - `_doCreate` 会 best-effort 地设置 bounds、请求透明，并缓存 `_transparentSupport[islandId]`。
   - 创建窗口后尝试 `postMessage(windowId, initialStructured)` 以及等待 `IslandChannel.waitForReady(windowId)`；若超时则使用 ping/pong 回退（handshake）。

2. 主进程更新：调用 `IslandManager().sendStructuredPayload(islandId, structured)` 或 `sendPayload(islandId, legacyDto)` 发送后续更新。
   - `sendPayload` 会先 `waitForReady`，然后最多重试 5 次 postMessage，失败会清除 cache 以便重新创建。

3. 子窗口 (`island_entry`) 接收并解析消息：
   - 通过 `globalChannel` 或 `controller.setWindowMethodHandler` 接收 `postWindowMessage` / `updateState`。
   - 若 payload 包含 `handshake: 'ping'`，会回复 `handshake_pong`。
   - 优先处理 `legacy` 字段；若含 `focusData`/`state` 则直接传递结构化 map；否则尝试 `IslandPayload.fromMap`。

4. 子窗口将用户操作或事件回传主进程：
   - 通过 `WindowController.fromWindowId('0').invokeMethod('onAction', {...})` 发送事件，例如 `ready`, `handshake_pong`, `bounds_changed`, `finish`, `abandon` 等。


## 5. 子窗口的 Windows 原生处理要点

- HWND 查找 (`_getIslandHwnd`)：使用 Win32 EnumWindows + GetWindowThreadProcessId，在当前 PID 的可见窗口中选择面积最小者作为岛窗口句柄并缓存。
- 无边框 + 透明：`_applyWin32FramelessTransparentImpl(hwnd)` 移除 WS_CAPTION 等样式，设置 `WS_EX_LAYERED` 并 `SetLayeredWindowAttributes` 使用 COLORKEY 实现透明。
- 拖动支持：子窗口处理 `startDragging` 调用时通过 `ReleaseCapture()` + `PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0)` 发起系统拖动。
- DPI / 缩放：使用 `GetDeviceCaps(hdc, LOGPIXELSX)` 获取 DPI，子窗口在设置物理尺寸及保存 bounds 时做逻辑<->物理像素转换。
- 定时上报位置：Timer 每 2s 获取当前物理 bounds，转换为逻辑尺寸并通过 `onAction` 报告 `bounds_changed` 以便主进程持久化。


## 6. IslandChannel 与消息可靠性

- `IslandChannel.ensureInitialized()` 在主进程 attach `WindowController.fromCurrentEngine()` 的处理器，监听来自子窗口的 `onAction` 回调，并将非 ready 的 action 通过 `actionStream` 广播。
- `waitForReady(windowId, timeout)` 支持按 windowId 的等待队列与匿名 FIFO；并有 `_readySet` 用于 sticky ready（处理 ready 到来早于等待者的情况）。
- `postMessage` / `createWindow` / `setWindowTransparent` 等方法都对 `MissingPluginException` 与一般异常做了容错处理。
- `sendPayload` 在失败时采用指数退避重试，若最终失败则清除缓存允许重建。


## 7. 常见操作示例（代码片段）

A. 在主进程创建并发送结构化 payload：

```dart
final islandId = 'island-1';
await IslandManager().createIsland(islandId);
final structured = {
  'state': 'focusing',
  'theme': 'light',
  'focusData': {
    'title': '读书',
    'timeLabel': '12:34',
    'isCountdown': true,
    'tags': ['学习'],
    'syncMode': 'local',
  },
  'transparentSupported': IslandManager().getTransparentSupport(islandId),
  'legacy': IslandPayload.fromMap(null).toMap(),
};
await IslandManager().sendStructuredPayload(islandId, structured);
```

B. 发送 legacy DTO：

```dart
final dto = IslandPayload(
  endMs: DateTime.now().millisecondsSinceEpoch + 25*60*1000,
  title: '专注',
  tags: ['study'],
  isLocal: true,
  mode: 0,
  style: 1,
  left: '',
  right: '',
  forceReset: false,
  topBarLeft: '',
  topBarRight: '',
  reminderQueue: [],
  detailType: '',
  detailTitle: '',
  detailSubtitle: '',
  detailLocation: '',
  detailTime: '',
  detailNote: '',
);
await IslandManager().sendPayload('island-1', dto);
```

C. 子窗口回复 ready（`island_entry` 已实现）：

```dart
await WindowController.fromWindowId('0').invokeMethod('onAction', {
  'action': 'ready',
  'windowId': controller.windowId,
});
```


## 8. 错误处理、重试与防抖

- 在多处使用 `try/catch` 并对宿主不支持的功能做 best-effort。常见异常包括 `MissingPluginException`、超时、postMessage 返回 false 等。
- `createIsland` 使用 `_creating` map 防止并发重复创建。
- `sendPayload` 最多重试 5 次、指数退避，失败后删除缓存 `_windowIdCache` 以触发重建。
- `recreateIsland` 有 1200ms 的冷却以避免循环重建。


## 9. 调试建议与常见问题

- 子窗口显示为黑色或不透明：
  - 检查宿主 plugin 是否实现 `setWindowTransparent`。`IslandManager` 会缓存透明支持结果并通过 `transparentSupported` 字段告知子窗口。
  - Windows 平台上，FFI 调用可能失败（权限、句柄获取失败），查看 `island_entry.dart` 的 `debugPrint` 日志。

- 子窗口不接收消息：
  - 确认 `createWindow` 成功并返回 `windowId`。
  - 确保 `IslandChannel.ensureInitialized()` 已调用并 attach handler（主进程侧）。

- ready 丢失/超时：
  - 代码有 handshake ping/pong 回退；若仍不稳定，检查宿主 plugin 的 `onAction` 实现及 `postWindowMessage` 能力。

- 调试方法：
  - 利用文件中已有大量 `debugPrint` 日志。
  - 子窗口在缺少 controller 时会 fallback 在主窗口内渲染 `IslandUI`，便于在不走多窗口环境下调试 UI。


## 10. 扩展建议与向后兼容

- 继续兼容 legacy DTO 以保证现有逻辑不被破坏；新字段优先放在结构化 payload 下。
- 若需更复杂的消息确认机制，可采用 `lib/windows_island/payload.dart` 中 `IslandPayload`（带 `msg_id`）进行消息追踪/ACK/超时重试。
- 支持多个岛：`IslandManager` 已按 `islandId` 缓存，可扩展为 `island-1`, `island-2` 等多实例支持。


## 11. 快速参考（方法签名与语义）

- 主进程：
  - `Future<String?> IslandManager().createIsland(String islandId)`
  - `Future<bool> IslandManager().sendStructuredPayload(String islandId, Map payload)`
  - `Future<bool> IslandManager().sendPayload(String islandId, IslandPayload payload)`
  - `Future<void> IslandManager().recreateIsland(String islandId)`
  - `Future<void> IslandManager().destroyCachedIsland(String islandId)`
  - `Future<String?> IslandChannel.createWindow(Map args)`
  - `Future<bool> IslandChannel.postMessage(String windowId, Map payload)`
  - `Future<bool> IslandChannel.setWindowTransparent(String windowId, bool transparent)`
  - `Future<bool> IslandChannel.waitForReady(String? windowId, {Duration timeout})`
  - `Stream<Map<String, dynamic>> IslandChannel.actionStream`

- 子窗口（`island_entry`）：
  - 接收：`postWindowMessage` / `updateState`（args: Map 或 {payload: Map}）
  - 发送：`WindowController.fromWindowId('0').invokeMethod('onAction', {...})`


## 12. FAQ（简短）

Q: 为什么有两个 `IslandPayload` 文件/概念？

A: `lib/windows_island/island_payload.dart` 为 legacy DTO（包含业务字段）。`lib/windows_island/payload.dart` 为通用消息封装（带 msg_id、type 等）。两者用途不同：前者用于业务数据，后者用于消息追踪/路由。不要混淆。


---

如果你希望我将该文档进一步翻译为英文、生成流程时序图、或把它放到仓库根 README 中的链接处，我可以继续处理。
