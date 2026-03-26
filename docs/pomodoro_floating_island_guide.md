# 番茄钟 / 悬浮窗（灵动岛）实现梳理与故障定位指南(已废弃)

本档为项目中关于“番茄钟（Pomodoro）”与桌面悬浮窗 / 灵动岛（Floating / Island）功能的全面说明、调用关系、恢复逻辑、用户设置与原生实现细节。把这份文档喂给我时，我能一眼判断“某个错误应该改哪个地方”。

> 位置：`docs/pomodoro_floating_island_guide.md`

----

## 目的
- 汇总相关源文件与职责。
- 说明 Flutter ↔ Native（Windows）桥接和参数契约。
- 详细解释两种悬浮窗样式（Classic / Island）的行为与切换机制。
- 说明 App 异常退出后如何恢复番茄钟并显示浮窗的完整流程。
- 说明窗口位置保存/恢复、强制复位逻辑及注册表键位。
- 给出“症状 → 定位点 → 检查项”快速排查表，便于快速定位并修复。

----

## 快速行动清单（Checklist）
1. 检查 Flutter 端偏好与 payload：`lib/services/float_window_service.dart`。
2. 检查设置 UI 是否保存并触发更新：`lib/screens/home_settings_screen.dart`。
3. 检查番茄钟 run-state 的持久化：`lib/services/pomodoro_service.dart`（`pomodoro_run_state`）。
4. 检查首页启动时恢复逻辑：`lib/screens/home_dashboard.dart`（`_checkAndNavigateToPomodoro()`）。
5. 检查 Flutter ↔ Windows Channel 名称与参数解析：`windows/runner/flutter_window.cpp`。
6. 检查 native 渲染 / 交互 / SaveState / LoadState：`windows/runner/float_window.h`、`float_window.cpp`。
7. 若是 Android / home_widget 问题，再检查 `lib/services/widget_service.dart` 与 `android/...` 插件文件。

----

## 主要文件与职责（概览）
- Flutter / Dart 层：
  - `lib/services/float_window_service.dart`
    - MethodChannel('com.math_quiz_app/float_window')。负责 build payload、发送 `showFloat`/`hideFloat`、处理 `onAction` 回调、读取 prefs（`float_window_enabled`/`float_window_style`/slots）并维护内部缓存 `_lastEndMs/_lastTitle/_lastTags/_lastIsLocal/_lastMode`。
    - `update(...)` 是核心，只有 Windows 时有效。
    - `resetPositions()`：将主窗口居中并调用 native 的 `showFloat` with `forceReset:true`。
  - `lib/services/pomodoro_service.dart`
    - 番茄钟模型与持久层。关键 key：`pomodoro_run_state`（用于防误杀恢复）、`pomodoro_settings_v2`、`pomodoro_tags_v2`。
    - 提供 `loadRunState() / saveRunState() / clearRunState()`，并通过 `onRunStateChanged` Stream 广播变更。
  - `lib/screens/pomodoro/views/workbench_view.dart`
    - 当番茄钟 start/stop/切换/标签变动时，调用 `_showLocalFloat()` → `FloatWindowService.update(...)` 以同步 native 窗口内容。
  - `lib/screens/home_dashboard.dart`
    - 启动恢复：`_checkAndNavigateToPomodoro()` 在首页启动后读取 `pomodoro_run_state`，若存在正在进行的 session，会调用 `FloatWindowService.update(...)` 并 push 到 `PomodoroScreen`。
  - `lib/screens/home_settings_screen.dart`
    - 用户设置读写（`float_window_enabled`, `float_window_style`, `float_window_left_slot`, `float_window_right_slot`），每次变更都会调用 `FloatWindowService.update()`。

- Windows 原生层：
  - `windows/runner/flutter_window.cpp`
    - 在 native 侧创建 MethodChannel `com.math_quiz_app/float_window`，解析 `showFloat` / `hideFloat` 并调用 `FloatWindow::instance().Show(...)` / `Hide()`。
    - 将 native 中 `action` 回调通过 `InvokeMethod("onAction", {action, modifiedSecs})` 发送到 Flutter（由 `PostMessage` 路由到主线程）。
  - `windows/runner/float_window.h` / `float_window.cpp`
    - `FloatWindow` 单例实现：管理窗口线程、渲染（GDI+）、交互、动画与状态机。
    - 枚举 `Style { Classic = 0, Island = 1 }` 与 `IslandState { Default, Hovered, FinishConfirm, AbandonConfirm, DetailCard, TopBar, FocusBar }`。
    - 保存/读取窗体位置与尺寸到注册表：`HKEY_CURRENT_USER\Software\MathQuiz\FloatV3`（键名：`X`,`Y`,`W`,`H`,`Alpha`，另有可选 `DefaultTop`）。
    - `Show(...)` 的参数与 Flutter 发送的 Map 对应；内部实现处理 `forceReset`、样式调整、动画触发与窗口创建/复用。

----

## Flutter ↔ Native 参数契约（MethodChannel）
- Channel 名称（必须一致）：
  - `com.math_quiz_app/float_window`

- Flutter 调用 native：
  - `showFloat` (Map) — 常用字段：
    - `endMs` (int, ms) — 目标结束时间（或 count-up 时的 sessionStartMs）
    - `title` (string)
    - `tags` (List<string>)
    - `isLocal` (bool)
    - `mode` (int) — 0 = countdown, 1 = countUp
    - `style` (int) — 0 = Classic, 1 = Island
    - `left` / `right` (string) — 左/右槽显示文本
    - `topBarLeft` / `topBarRight` (string)
    - `reminderQueue` (List<Map<string,string>>)
    - `detail_type`, `detail_title`, `detail_subtitle`, `detail_location`, `detail_time`, `detail_note`
    - `forceReset` (bool)
  - `hideFloat` — 隐藏窗口。

- Native 调用 Flutter：
  - `onAction` — Map { `action`: 'finish'|'abandon', `modifiedSecs`: int }
    - Flutter 在 `FloatWindowService.init()` 中注册 `setMethodCallHandler` 并在 `onAction` 时调用 `_handleAction(...)`，处理 finish/abandon（记录/清理/同步）并最终调用 `FloatWindowService.update()`。

----

## 两种样式行为详解与差异

### Classic (Style::Classic)
- 外观：大卡片，上部为倒计时/计时区域，下部为任务/标签行，中间有分割线。
- 交互：支持拖拽移动与右下角缩放；有右上 × 关闭按钮。
- 自动隐藏：`WM_TIMER`（1s）里会检测 `if (mode_==0 && style_==Classic && nowMs >= endMs_) Hide()`。
- 用例：更传统、信息密度大，适合专注计时显示。

### Island (Style::Island)
- 外观：胶囊（pill）+ 可展开的 Detail Card / TopBar / FocusBar。
- 状态机：`IslandState` 包含 Default、Hovered、FinishConfirm、AbandonConfirm、DetailCard、TopBar、FocusBar 等。
- 交互细节：
  - Hover（或 mouse enter）会展开并显示 ✓/✗ 按钮（若为本地专注 session）。
  - 点击 ✓ 进入 FinishConfirm，可带 `modifiedSecs`（特别是 count-up 情况）；确认后通过 action 回调给 Flutter。
  - 点击 pill 可展开为 DetailCard，显示 `detailCard_` 的丰富信息（来自 `detail_*` 字段）。
  - 支持提醒队列（`reminderQueue_`）和 TopBar 展示（`topBarLeft_/topBarRight_`）。
- 动画：使用 `anim_`（收缩→展开）与 `heightAnim_`（DetailCard 高度动画）。

### 样式切换流程
1. 用户在设置页改 `float_window_style` → Flutter 写 prefs 并调用 `FloatWindowService.update()`。
2. `FloatWindowService.update()` 读取 prefs 的 `style` 并把它包含在 `showFloat` payload。
3. Native 在 `flutter_window.cpp` 的 MethodCall Handler 中解析并调用 `FloatWindow::Show(... style=...)`，native 会 `style_ = (Style)style` 并相应调整尺寸/动画/状态。

注意：若窗口已存在，`Show()` 有专门逻辑来 reapply 新的 size/anim/SetWindowPos；如果没有触发动画/Render，可能是 `Show()` 中未设置 `SetTimer` 或没有触发 `PostMessage` 强制重绘。

----

## 异常退出 / 恢复逻辑（详述）
- 数据持久化根源：`PomodoroService.saveRunState()` 将当前运行的 `PomodoroRunState` 序列化为 JSON 存入 SharedPreferences 的 `pomodoro_run_state`。
- App 重启或前台恢复时的流程：
  1. App 启动初始化（`main.dart::_initializeApp()`）会调用 `FloatWindowService.init()` 并在 Windows 上调用一次 `FloatWindowService.update()`（该次调用如果缺少参数可能只做空状态更新）。
  2. 首页（`HomeDashboard`）在 `initState` 的 postFrameCallback 中调用 `_checkAndNavigateToPomodoro()`：
     - `PomodoroService.loadRunState()` -> 若存在且 phase 为 focusing/breaking，并且倒计时仍没结束（countdown：targetEndMs - now > 0；countUp：按 sessionStartMs 恢复），会：
       - 在 Windows 且 `float_window_enabled` 为 true 时调用 `FloatWindowService.update(endMs: ..., title: ..., tags: ..., isLocal: true, mode: ...)`，将当前状态推送给 native 悬浮窗；
       - 跳转到 `PomodoroScreen`（计时页）。
  3. 运行过程中 `PomodoroService.onRunStateChanged` 会广播状态改变，页面与 `FloatWindowService.update()` 会相应更新渲染与 native 窗口。

要点：若你只在 `main.dart` 调用了 `FloatWindowService.update()`（无参数），但首页没执行恢复流程或 `loadRunState()` 没被读取，浮窗可能不会显示正确的计时数据。可靠恢复依赖 `HomeDashboard._checkAndNavigateToPomodoro()` 的调用。

----

## 窗口位置 & 持久化细节
- 存储位置：Windows 注册表 `HKEY_CURRENT_USER\\Software\\MathQuiz\\FloatV3`（常用键：`X`,`Y`,`W`,`H`,`Alpha`，并有 `DefaultTop` 用于 forceReset）。
- 保存时机：用户完成拖拽或缩放时在 `WM_LBUTTONUP` 分支会触发 `SaveState()` 写注册表。
- 恢复时机：窗口线程启动时 `LoadState()` 读取并做 clamp（防止显示器配置变更导致窗口不可见）。
- 强制复位：`FloatWindowService.resetPositions()` 会在 Flutter 层尽量把主窗口居中并调用 native 的 `showFloat` with `forceReset:true`；native 的 `Show()` 在 `forceReset` 下会把 `winX_/winY_` 置中或使用注册表里的 `DefaultTop`。

----

## 常见故障 & 快速定位（Symptoms → Files → 检查点）

1. 悬浮窗不弹出 / 没内容（Windows）
   - 检查点：
     - `home_settings_screen.dart`：`float_window_enabled` 是否为 true？
     - `HomeDashboard._checkAndNavigateToPomodoro()`：在 App 启动后是否读取了 `pomodoro_run_state` 并调用 `FloatWindowService.update(...)`？
     - `float_window_service.dart`：`update()` 是否被调用并打印 `[FloatWindow] showFloat ...`？
     - `flutter_window.cpp`：MethodChannel handler 是否接收到 `showFloat`？（可临时增加日志）。

2. 切换样式后窗口无变化
   - 检查点：
     - `home_settings_screen.dart`：是否写入 prefs 并调用 `FloatWindowService.update()`？
     - `float_window_service.dart`：`style` 是否被包含在 payload？
     - `float_window.cpp`：`Show(... style)` 是否把 `style_ = (Style)style` 且触发动画/SetTimer/SetWindowPos。

3. 用户在 native 点击 Finish/Abandon，但 Flutter 没反应
   - 检查点：
     - `flutter_window.cpp`：native 是否通过 `InvokeMethod("onAction", ...)` 发送到 Flutter？
     - `float_window_service.dart`：`init()` 是否被调用以注册 handler？（`main.dart` 在初始化时应调用 `FloatWindowService.init()`）。
     - `pomodoro_service.dart`：`loadRunState()` 是否返回期望的 run-state（若为空，`_handleAction` 有分支处理可能导致早期返回）。

  6. 灵动岛在 Remote session 下只显示时钟，不进入番茄钟状态，或在进入番茄钟界面后立即退回为默认时钟
     - 症状描述：当有远端（其他设备）正在进行专注时，App 首页的横幅显示正常，但原生灵动岛仅显示时间，不进入专注计时状态。手动在设置里强制刷新会让灵动岛进入番茄钟状态，但一旦打开番茄钟界面，灵动岛又恢复成默认时钟。
     - 定位点：`lib/services/float_window_service.dart`
     - 根因分析：部分调用方会以 `endMs: 0` 或直接调用 `update()` 以刷新 TopBar 或隐藏浮窗，但没有传入 `isLocal`/`mode` 等参数。原先 `update()` 在接收 null 时使用默认值（`isLocal=true`, `mode=0`），导致之前由远端（`isLocal=false`）传入的状态被意外覆盖，native 在下一次 `showFloat` 时收到错误的 `isLocal`/`mode`，从而显示为普通时钟或在进入番茄钟页面后被重置。
     - 解决办法：在 `float_window_service.dart` 中修改 `update()`：当调用者没有提供 `isLocal`/`mode` 时，保留 `_lastIsLocal` 和 `_lastMode` 的先前值，而不是使用硬编码默认值。这样短暂的无参刷新不会破坏远端会话的标记。
     - 已修复文件与位置：`lib/services/float_window_service.dart` — 修改 `update()` 中对传入 null 值的处理，改为保留先前值；并在发送 `showFloat` 时打印日志以便调试。

4. 位置保存 / 恢复异常（窗口消失或位置跑到不可见处）
   - 检查点：
     - `float_window.cpp`：`SaveState()` 写入值是否合理；`LoadState()` 中 clamp 到当前虚拟屏幕的逻辑是否正确（看 `GetSystemMetrics(SM_XVIRTUALSCREEN...)` 与 margin）。
     - 若用户使用多显示器或分辨率改变，确认 `LoadState()` 里对 `maxX/maxY/minX/minY` 的计算没有越界。

5. Classic 未在倒计时结束时自动隐藏
   - 检查点：
     - `float_window.cpp` 的 `WM_TIMER`（wParam==1）分支含有 `if (self->mode_ == 0 && self->style_ == Style::Classic && nowMs >= self->endMs_) { self->Hide(); return 0; }`。
     - 确认 Flutter 传给 `endMs` 单位为毫秒且值正确。

----

## 调试建议与快速修复步骤
- 在 Flutter 侧先确认：
  - `FloatWindowService.update()` 有打印日志（`print('[FloatWindow] showFloat style=$style endMs=$_lastEndMs mode=$_lastMode title=$_lastTitle')`）。若没有打印说明 Flutter 未调用或早期返回。
  - 在设置页切换样式后观察是否立即打印并且 native 有响应。
- 在 Native 侧（Windows）：
  - 在 `windows/runner/flutter_window.cpp` 的 MethodCall Handler 的 `showFloat` 分支里临时插入 `OutputDebugStringW` 或写文件以确认是否已接收参数并解析成功。
  - 在 `float_window.cpp` 的 `Show()`、`LoadState()`、`SaveState()` 中加入日志以排查位置与 style 应用情况。
- 恢复问题测试：
  1. 在模拟器/真实机上手动将 SharedPreferences 中 `pomodoro_run_state` 写成有效的 focusing state；
  2. 重启 App / 直接从首页触发 `_checkAndNavigateToPomodoro()`；
  3. 检查是否调用了 `FloatWindowService.update(endMs:...)` 并且 native 收到 `showFloat`。

----

## 开发者快速跳转（文件清单）
- Flutter 层：
  - `lib/services/float_window_service.dart`  （核心）
  - `lib/services/pomodoro_service.dart`     （run-state 持久化）
  - `lib/screens/home_settings_screen.dart` （设置 & 触发点）
  - `lib/screens/pomodoro/views/workbench_view.dart`（调用浮窗的 UI）
  - `lib/screens/home_dashboard.dart`        （启动恢复逻辑）
  - `lib/main.dart`                          （初始化 `FloatWindowService.init()`）

- Windows 原生：
  - `windows/runner/flutter_window.cpp`      （MethodChannel 解析）
  - `windows/runner/float_window.h`         （声明）
  - `windows/runner/float_window.cpp`       （渲染/交互/保存/恢复/动画）

- 其他可能相关：
  - `lib/services/pomodoro_sync_service.dart`（跨设备同步，影响 isLocal 标识与 remote 状态）
  - `lib/services/widget_service.dart`（home_widget 相关）
  - Android widget 代码（如果需要 mobile widget 同步）：`android/.../TodoWidgetProvider.kt`, `MainActivity.kt` 等

----

## 使用此文档时如何快速定位并修复一个具体 bug
1. 先把错误现象用一句话描述发送给我（例如："切换到灵动岛样式后，点击 ✓ 未触发 finish"）。
2. 我会根据本档的“症状→定位点”表直接指出需修改的确切文件和函数，并给出最小可行的补丁（native 或 Flutter）。
3. 我会在仓库内应用补丁并运行静态检查（`get_errors`），若通过则提示你如何在本地构建并验证；否则迭代修正最多 3 次直到通过。

----

## 搜索关键词（便于快速查找）
- `com.math_quiz_app/float_window`
- `float_window_service`
- `float_window_style`, `float_window_enabled`, `float_window_left_slot`, `float_window_right_slot`
- `pomodoro_run_state`, `pomodoro_settings_v2`
- `FloatWindow::Show`, `Style::Island`, `IslandState`
- 注册表键：`Software\\MathQuiz\\FloatV3`

----

## 结语
把这份 `docs/pomodoro_floating_island_guide.md` 文档当作“故障定位手册”。你每次把该文档喂给我并附上具体的错误现象或日志，我会直接定位到要改的文件与代码区域并给出修补补丁（包含本地复现/测试建议）。

如果你现在想让我直接修复或验证某个具体问题，请把重现步骤/日志/截图发来。我会在仓库里直接修改相应文件并运行检查。

