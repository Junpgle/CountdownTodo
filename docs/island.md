纯 Flutter 多窗口灵动岛重构方案与逻辑全景图

核心思想： 废弃原生 C++ 渲染，主程序与悬浮窗分别运行在两个隔离的 Flutter Isolate（内存空间）中，通过底层的 Event Channel 进行高速 JSON 通信。灵动岛的 UI、动画、主题适配全部由 Flutter 引擎接管。

一、 技术栈与核心依赖

窗口管理与生成： desktop_multi_window (用于创建独立的悬浮窗进程) + window_manager (用于辅助控制主窗口的置顶/隐藏逻辑)。

动画驱动： Flutter 原生的 AnimatedContainer, AnimatedPositioned, AnimatedSize 以及 Curves 弹性曲线。

状态管理： 悬浮窗内部推荐使用简易的 ValueNotifier 或 Provider 来响应跨窗口传来的 JSON 状态流。

二、 跨窗口通信协议 (IPC 契约)

由于主窗口和悬浮窗运行在不同的 Isolate 中，它们不能直接共享内存变量。FloatWindowService 的职责从“调用 C++”变成了“向子窗口发送 JSON Payload”。

1. Main -> Island (下发 UI 状态)

主窗口通过 WindowController.invokeMethod('updateState', payload) 发送完整的视图数据：

{
"state": "split_alert", // 枚举：idle, hover_wide, focusing, focus_control, split_alert, stacked_card, finish_confirm, abandon_confirm
"theme": "dark", // 严格控制深浅色
"focusData": {
"title": "计算机组成原理",
"timeLabel": "20:05",
"isCountdown": true,
"tags": ["考研", "硬核"]
},
"reminderData": {
"title": "📅 计组 20分钟后",
"location": "敬亭428(备注)",
"time": "20:30-21:30"
},
"dashboardData": { // 宽岛探针数据
"leftSlot": "10天 清明假期",
"rightSlot": "计组 8:00开始"
}
}


2. Island -> Main (回传用户操作)

悬浮窗通过 DesktopMultiWindow.invokeMethod('onAction', action) 向主应用汇报指令：

{"action": "finish_focus"} -> 结束专注

{"action": "abandon_focus"} -> 放弃专注

{"action": "reminder_done"} -> 提醒已读

{"action": "request_snooze"} -> 稍后排期（主应用收到后，立即拉起主窗口居中显示时间选择器）

三、 Flutter 侧的状态机与动画映射 (降维打击)

在 Flutter 中，之前你在草图中设计的那些复杂的形变，现在只需要改变几个变量，Flutter 会自动帮你做关键帧插值动画。

1. 细胞分裂动画 (Split Alert)

实现原理： 使用 Stack + 两个 AnimatedPositioned 胶囊。

平时状态： 提醒胶囊的 left / right 坐标和专注胶囊完全重合，且 opacity: 0。

分裂触发： 专注胶囊的 left 偏移量变小（向左移），提醒胶囊的 left 变大（向右挤出），opacity 变为 1。配合 Curves.easeOutBack，瞬间就能实现完美的弹性挤出效果。

2. 纵向居中重组 (Stacked Card)

实现原理： 监听点击事件后，将外层容器的 width 和 height 通过 AnimatedContainer 瞬间撑开。

内部布局： 将原本横向的 Row 或 Stack 切换为 Column（或动态调整 AnimatedPositioned 的 Y 轴坐标）。左侧的胶囊平滑移动到 top: 0, right: center，底部展开红绿按钮。

3. 防手滑二次确认 (Confirm Flip)

实现原理： 这是一个典型的局部状态翻转。在卡片内部维护一个简单的枚举变量。

当处于 FinishConfirm 时，左侧渲染绿色的 <确认> Widget，右侧渲染红色的 <手滑了> Widget。Flutter 的 AnimatedSwitcher 可以让这两个按钮在切换时自带优雅的淡入淡出或旋转动画。

四、 桌面悬浮窗的三大“坑点”与 Flutter 解法

难题 1：透明区域的鼠标穿透 (Hit-Test)

痛点： 如果我们把悬浮窗创建得很大（为了容纳展开后的卡片），那么透明区域会挡住用户点击下方的桌面软件。

Flutter 解法（动态调整窗口尺寸）：
这是最完美的方案。悬浮窗内的代码，在每次执行展开/收缩动画前，实时调用 WindowController.setWindowSize(Size)。

Idle 态：窗口极小（例如 150x50）。

Hover Wide 态：瞬间将窗口物理尺寸变宽（例如 500x50），然后播放胶囊延展动画。

Stacked Card 态：将窗口物理尺寸变高（例如 300x200）。
这样，Flutter 窗口的物理边界永远紧紧包裹着 UI，绝对不会误挡用户的鼠标穿透！

难题 2：无边框窗口的拖拽 (Window Dragging)

痛点： 移除了 C++ 代码后，原生的标题栏拖拽没了。

Flutter 解法： 在整个灵动岛的最外层 Widget 上，套一个 GestureDetector：

GestureDetector(
onPanUpdate: (details) {
WindowController.fromWindowId(windowId).startDragging();
},
child: IslandUI(),
)


仅仅三行代码，就能恢复丝滑的任意位置拖拽。

难题 3：极致的深浅色主题防错

痛点： 之前总是担心深浅色搞混。

Flutter 解法： 彻底抛弃硬编码颜色。在悬浮窗的 MaterialApp 中统一定义 ThemeData。

// 浅色模式阴影护城河
BoxShadow(
color: isDarkMode ? Colors.transparent : Colors.black.withOpacity(0.15),
blurRadius: 10,
spreadRadius: 2,
)


通过统一的 BoxDecoration，深色模式极暗无阴影，浅色模式纯白带深色弥散阴影，从底层切断 UI 渲染混淆的可能。

五、 实施重构的“三步走”战略

第一步（拔除旧桩）：

删除 windows/runner/float_window.cpp 和 .h。

清理 flutter_window.cpp 中旧的 MethodChannel 注册代码。

第二步（搭建新岛）：

引入 desktop_multi_window。

在 lib/main.dart 中配置多窗口入口（识别 args.first == 'multi_window'）。

创建全新的 lib/screens/island/island_screen.dart，纯写静态 UI（先把 5 种状态的样子用 Widget 画出来，配好颜色和阴影）。

第三步（神经接入）：

重构 FloatWindowService，将其改造为使用 MultiWindow IPC 发送 Payload。

接入 Hover、Click 和 各种动画，测试动态调整窗口大小 API (setWindowSize)。