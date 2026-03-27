纯 Flutter 多窗口灵动岛重构方案与逻辑全景图

核心思想：废弃原生 C++ 渲染，主程序与悬浮窗分别运行在两个隔离的 Flutter Isolate（内存空间）中，通过底层的 Event Channel 进行高速 JSON 通信。灵动岛的 UI、动画、主题适配、以及本地/远端控制权限，全部由 Flutter 引擎接管。

一、 技术栈与核心依赖

窗口管理与生成：desktop_multi_window (用于创建独立的悬浮窗进程) + window_manager (用于辅助控制主窗口的置顶/隐藏逻辑)。

动画驱动：Flutter 原生的 AnimatedContainer, AnimatedPositioned, AnimatedSize, AnimatedSwitcher 以及 Curves 弹性曲线。

状态管理：悬浮窗内部推荐使用简易的 ValueNotifier 或 Provider 来响应跨窗口传来的 JSON 状态流。

二、 跨窗口通信协议 (IPC 契约)

由于主窗口和悬浮窗运行在不同的 Isolate 中，无法直接共享内存变量。FloatWindowService 的职责转变为“向子窗口发送标准化的 JSON Payload”。

1. Main -> Island (下发 UI 状态与控制权限)

主窗口通过 WindowController.invokeMethod('updateState', payload) 发送完整的视图数据。特别引入 syncMode 字段以区分本地与远端番茄钟。

{
"state": "split_alert", // 枚举：idle, hover_wide, focusing, focus_control, split_alert, stacked_card, finish_confirm, abandon_confirm
"theme": "dark",        // 严格控制深浅色
"focusData": {
"title": "计算机组成原理",
"timeLabel": "20:05",
"isCountdown": true,
"tags": ["考研", "硬核"],
"syncMode": "local"   // 新增：区分番茄钟来源 ["local" (本地控制), "remote" (远端监视)]
},
"reminderData": {
"title": "📅 计组 20分钟后",
"location": "敬亭428(备注)",
"time": "20:30-21:30"
},
"dashboardData": {      // 宽岛探针数据
"leftSlot": "10天 清明假期",
"rightSlot": "计组 8:00开始"
}
}


2. Island -> Main (回传用户操作)

悬浮窗通过 DesktopMultiWindow.invokeMethod('onAction', action) 向主应用汇报指令。当且仅当 syncMode == "local" 时，悬浮窗才允许发送终止操作：

{"action": "finish_focus"} -> 提前结束专注（仅 local 有效）

{"action": "abandon_focus"} -> 放弃专注（仅 local 有效）

{"action": "reminder_done"} -> 提醒已读

{"action": "request_snooze"} -> 稍后排期（主应用收到后，立即拉起主窗口居中显示时间选择器）

三、 Flutter 侧的状态机、动画映射与双态逻辑

1. 本地/远端双态 UI 隔离 (The Dual-State Logic)

根据 syncMode 动态屏蔽交互：

Local (本地开启)：支持鼠标 Hover 展开（进入 focus_control 态），展示 [结束] 与 [放弃] 按钮。

Remote (远端开启)：屏蔽控制面板的展开操作，或者在展开时仅展示“远端设备专注中”的占位 UI。点击只触发时间面板的详情预览，不提供中断操作。

2. 细胞分裂动画 (Split Alert)

实现原理：使用 Stack + 两个 AnimatedPositioned 胶囊。

平时状态：提醒胶囊的 left / right 坐标和专注胶囊完全重合，且 opacity: 0。

分裂触发：专注胶囊的 left 偏移量变小（向左移），提醒胶囊的 left 变大（向右挤出），opacity 变为 1。配合 Curves.easeOutBack，瞬间实现完美的弹性挤出效果。

3. 纵向居中重组 (Stacked Card)

实现原理：监听点击事件后，将外层容器的 width 和 height 通过 AnimatedContainer 瞬间撑开。

内部布局：将原本横向的 Row 或 Stack 切换为 Column（或动态调整 AnimatedPositioned 的 Y 轴坐标）。左侧的胶囊平滑移动到 top: 0, right: center，底部展开控制按钮（如果 syncMode == "local"）。

4. 防手滑二次确认 (Confirm Flip)

实现原理：典型局部状态翻转。当处于 FinishConfirm 或 AbandonConfirm 时，利用 Flutter 的 AnimatedSwitcher 将常规按钮替换为红绿确认按钮，自带优雅的淡入淡出或旋转翻转动画。

四、 桌面悬浮窗的三大“坑点”与 Flutter 解法

难题 1：透明区域的鼠标穿透 (Hit-Test)

痛点：若悬浮窗尺寸固定很大，透明区域会挡住下方的桌面软件点击。
Flutter 解法（动态调整边界）：每次执行展开/收缩动画前，先行调用 WindowController.setWindowSize(Size) 改变操作系统的物理窗口大小。

Idle 态：窗口极小（例如 150x50）。

Hover Wide 态：瞬间变宽（500x50），再播放内部延展动画。

Stacked Card 态：瞬间变高（300x200）。

结果：物理边界永远紧裹 UI，零误挡。

难题 2：无边框窗口的拖拽 (Window Dragging)

痛点：移除了 C++ 代码后，原生的标题栏拖拽失效。
Flutter 解法：在灵动岛最外层包一层手势检测。

GestureDetector(
onPanUpdate: (details) {
WindowController.fromWindowId(windowId).startDragging();
},
child: IslandUI(),
)


难题 3：极致的深浅色主题防错

痛点：跨进程的主题容易搞混。
Flutter 解法：彻底抛弃硬编码颜色，基于 IPC 传来的 theme 字段全局重建 ThemeData。

// 浅色模式阴影护城河
BoxShadow(
color: isDarkMode ? Colors.transparent : Colors.black.withOpacity(0.15),
blurRadius: 10,
spreadRadius: 2,
)


深色极暗无阴影，浅色纯白带弥散阴影，底层切断渲染混淆。

五、 实施重构的“三步走”战略

第一步（拔除旧桩）：

删除 windows/runner/float_window.cpp 和 .h。

清理主应用中旧的 C++ MethodChannel 注册代码。

第二步（搭建新岛）：

引入 desktop_multi_window，在 lib/main.dart 中配置多窗口路由（识别 args.first == 'multi_window'）。

纯写静态 UI（先 mock 数据把 Idle, Split, Control (本地/远端), Confirm 等状态画出来）。

第三步（神经接入）：

重写 FloatWindowService 为 MultiWindow IPC 驱动。

接入 Hover 判定、Click 事件。

重点调试 setWindowSize 与 Flutter 内部动画的配合时序，确保不出现截断裁剪。