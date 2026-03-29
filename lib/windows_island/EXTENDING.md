# 灵动岛模块 - 扩展开发指南

## 目录
1. [架构概览](#架构概览)
2. [用户交互流程](#用户交互流程)
3. [核心概念](#核心概念)
4. [扩展点](#扩展点)
5. [IPC 通信](#ipc-通信)
6. [最佳实践](#最佳实践)
7. [问题排查](#问题排查)

---

## 架构概览

### 模块结构

```
lib/windows_island/
├── island_config.dart         # 集中管理的常量和配置
├── island_channel.dart        # 与主应用的 IPC 通信
├── island_debug.dart          # 调试/测试页面
├── island_entry.dart          # 窗口入口点 (islandMain)
├── island_manager.dart        # 窗口生命周期管理
├── island_payload.dart        # 数据传输对象
├── island_reminder.dart       # 提醒服务
├── island_state_handler.dart  # 可扩展的状态管理
├── island_state_stack.dart    # 栈式状态管理核心
├── island_ui.dart             # UI 组件（使用栈式状态机）
└── island_win32.dart          # Win32 API 工具函数
```

### 核心：IslandStateStack

```
┌─────────────────────────────────────────────────────────────┐
│                    IslandStateStack                         │
├─────────────────────────────────────────────────────────────┤
│  push(state, {data})      → 入栈临时状态                    │
│  pop(expectedState)       → 出栈恢复下层                    │
│  replaceTop(state, {data}) → 替换栈顶                       │
│  replaceBase(state, {data}) → 替换栈底                      │
│  clearToIdle()            → 清空回 idle                     │
├─────────────────────────────────────────────────────────────┤
│  current    → 当前显示状态（栈顶）                          │
│  base       → 基础状态（栈底：idle 或 focusing）            │
│  isProtected → 当前是否受保护                               │
└─────────────────────────────────────────────────────────────┘
```

### 数据流

```
HomeDashboard
  └── FloatWindowService.update()
        └── IslandDataProvider.buildPayload()
              └── IslandManager.sendStructuredPayload()
                    └── Island Window (island_entry.dart)
                          └── IslandUI
                                └── IslandStateStack
                                      ├── push()   // 入栈展示
                                      ├── pop()    // 出栈恢复
                                      ├── replaceTop()  // 替换栈顶
                                      └── replaceBase() // 替换栈底
```

---

## 用户交互流程

### 1. 时钟状态 (Idle)

**初始状态**：灵动岛显示当前时间

```
┌──────────────┐
│   14:30      │  ← 点击/悬停区域
└──────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 |
|----------|----------|--------|----------|
| 点击时钟 | 展开为 hoverWide | `[idle] → [idle, hoverWide]` | 120x34 → 380x46 |
| 拖动时钟 | 移动窗口位置 | 不变 | 不变 |
| 悬停时钟 | 展开为 hoverWide (100ms延迟) | `[idle] → [idle, hoverWide]` | 120x34 → 380x46 |
| 鼠标离开 | 收回 (120ms延迟) | `[idle, hoverWide] → [idle]` | 380x46 → 120x34 |

---

### 2. 专注状态 (Focusing)

**触发条件**：主应用发送 `state: 'focusing'`

```
┌──────────────┐
│  专注事项    │
│   25:00      │  ← 点击展开详情
└──────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击胶囊 | 展开 stackedCard | `[focusing] → [focusing, stackedCard]` | 100x46 → 280x140 | - |
| 拖动胶囊 | 移动窗口 | 不变 | 不变 | - |
| 悬停 | 展开 hoverWide | `[focusing] → [focusing, hoverWide]` | 100x46 → 380x46 | - |

---

### 3. 详情卡片 (StackedCard)

```
┌────────────────────────┐
│ 14:30 | 学习任务       │
│ #学习 #数学            │
│ ┌──────┐  ┌──────┐     │
│ │ 完成 │  │ 放弃 │     │
│ └──────┘  └──────┘     │
└────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击空白 | 收回 focusing | `pop(stackedCard)` → `[focusing]` | 280x140 → 100x46 | - |
| 点击"完成" | push finishConfirm | `[focusing, stackedCard, finishConfirm]` | → 260x130 | - |
| 点击"放弃" | push abandonConfirm | `[focusing, stackedCard, abandonConfirm]` | → 260x130 | - |

---

### 4. 完成确认 (FinishConfirm) ✓ 受保护

```
┌────────────────────────┐
│      确认完成?          │
│ 学习任务 | 25:00        │
│ ┌──────┐  ┌──────┐     │
│ │ 确认 │  │手滑了│     │
│ └──────┘  └──────┘     │
└────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"确认" | 发送 action → clearToIdle → push finishFinal | `[idle, finishFinal]` | → 260x130 | `finish` + secs |
| 点击"手滑了" | pop 回 stackedCard | `pop(finishConfirm)` → `[focusing, stackedCard]` | → 280x140 | - |

---

### 5. 放弃确认 (AbandonConfirm) ✓ 受保护

```
┌────────────────────────┐
│      确认放弃?          │
│ 学习任务 | 25:00        │
│ ┌──────┐  ┌──────┐     │
│ │手滑了│  │ 确认 │     │  ← 按钮位置相反
│ └──────┘  └──────┘     │
└────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"手滑了" | pop 回 stackedCard | `pop(abandonConfirm)` → `[focusing, stackedCard]` | → 280x140 | - |
| 点击"确认" | 发送 action → clearToIdle | `[idle]` | → 120x34 | `abandon` |

---

### 6. 完成最终 (FinishFinal) ✓ 受保护

```
┌────────────────────────┐
│      专注完成           │
│ 学习任务 | 25:00        │
│       ┌──────┐         │
│       │ 好的 │         │
│       └──────┘         │
└────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"好的" | clearToIdle | `[idle]` | → 120x34 | - |

---

### 7. 复制链接 (CopiedLink) ✓ 受保护 + 自动消失(10s)

```
┌──────────────────────────────────────┐
│ 🔗 已复制: example.com    [打开] [✕] │
└──────────────────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"打开" | 发送 action → pop | `pop(copiedLink)` → 恢复下层 | → 恢复 | `open_link` + url |
| 点击"✕" | 取消定时器 → pop | `pop(copiedLink)` → 恢复下层 | → 恢复 | - |
| 等待10秒 | 自动 pop | `pop(copiedLink)` → 恢复下层 | → 恢复 | - |

**时序**：
```
剪贴板检测URL
  └─→ FloatWindowService._showCopiedLinkIsland()
        └─→ IslandUI._pushWithAutoDismiss(copiedLink, 10s)
              │
              ├─→ 用户点击"打开" → onAction('open_link') → pop()
              ├─→ 用户点击"✕" → pop()
              └─→ 10秒后自动 pop()
```

---

### 8. 提醒胶囊 (ReminderCapsule)

```
┌────────────────────────┐
│ 📝 会议 15min          │  ← 点击展开
└────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击胶囊 | push reminderPopup | `[reminderCapsule, reminderPopup]` | → 320x150+ | - |

---

### 9. 提醒弹窗 (ReminderPopup) ✓ 受保护

```
┌──────────────────────────────────┐
│ 📝 待办：会议                    │
│ 301会议室                        │
│ 14:00 ~ 15:00 | 还有15分钟开始   │
│ ┌──────┐      ┌──────────┐      │
│ │ 好的 │      │ 稍后提醒  │      │
│ └──────┘      └──────────┘      │
└──────────────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"好的" | 发送 action → pop | `pop(reminderPopup)` → 恢复 | → 恢复 | `reminder_ok` |
| 点击"稍后提醒" | 发送 action → pop | `pop(reminderPopup)` → 恢复 | → 恢复 | `remind_later` |

---

### 10. 双胶囊提醒 (ReminderSplit)

```
┌──────────────────────────────────────────────┐
│  🎯 25:00          📝 会议 15min             │  ← 紧凑模式
└──────────────────────────────────────────────┘

点击右侧胶囊后展开：

┌──────────────────────────────────────────────┐
│  🎯 25:00          📝 会议 15min             │
├──────────────────────────────────────────────┤
│ 📝 待办：会议                                 │
│ 301会议室                                     │
│ 14:00 ~ 15:00 | 还有15分钟开始                │
│ ┌──────┐                     ┌──────────┐    │
│ │ 好的 │                     │ 稍后提醒  │    │
│ └──────┘                     └──────────┘    │
└──────────────────────────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击左侧胶囊 | 展开/收起专注详情 | 不变，更新 `_expandedReminderPart` | 480x46 ↔ 320x300 | - |
| 点击右侧胶囊 | 展开/收起提醒详情 | 不变，更新 `_expandedReminderPart` | 480x46 ↔ 320x300 | - |
| 展开后点"好的" | replaceTop focusing | `replaceTop(focusing)` | → 100x46 | `reminder_ok` |
| 展开后点"稍后提醒" | replaceTop focusing | `replaceTop(focusing)` | → 100x46 | `remind_later` |

---

### 11. HoverWide 展开

```
┌──────────────────────────────────────────────────────────────────────────┐
│ 待办事项              │ 14:30 │              13:00 课程                   │
└──────────────────────────────────────────────────────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 |
|----------|----------|--------|----------|
| 鼠标悬停 | push hoverWide (100ms) | `[base, hoverWide]` | → 380x46 |
| 鼠标离开 | pop hoverWide (120ms) | `pop()` → `[base]` | → 恢复 |
| 点击区域 | 如果 focusing → pop后push stackedCard | → `[focusing, stackedCard]` | → 280x140 |

---

## 核心概念

### IslandStateStack API

```dart
// 创建栈
final stack = IslandStateStack();

// 入栈：临时状态
stack.push(IslandState.copiedLink, data: payload);

// 出栈：恢复下层
final restored = stack.pop(IslandState.copiedLink);

// 替换栈顶：reminderSplit 替换 focusing
stack.replaceTop(IslandState.reminderSplit, data: payload);

// 替换栈底：idle <-> focusing 切换
stack.replaceBase(IslandState.focusing, data: payload);

// 清空回 idle
stack.clearToIdle();

// 检查属性
stack.current      // 当前状态
stack.base         // 基础状态
stack.isProtected  // 是否受保护
stack.length       // 栈深度
```

### 受保护状态

```dart
static const protectedStates = {
  IslandState.finishConfirm,   // 完成确认
  IslandState.abandonConfirm,  // 放弃确认
  IslandState.finishFinal,     // 完成最终
  IslandState.copiedLink,      // 复制链接
  IslandState.reminderPopup,   // 提醒弹窗
};
```

外部 payload 无法覆盖受保护状态。

### 状态枚举

```dart
enum IslandState {
  idle,              // 时钟
  focusing,          // 专注计时
  hoverWide,         // 悬停展开
  stackedCard,       // 详情卡片
  splitAlert,        // 分屏通知
  finishConfirm,     // 完成确认 ✓
  abandonConfirm,    // 放弃确认 ✓
  finishFinal,       // 完成最终 ✓
  reminderPopup,     // 提醒弹窗 ✓
  reminderSplit,     // 双胶囊提醒
  reminderCapsule,   // 单胶囊提醒
  copiedLink,        // 复制链接 ✓
}
```

---

## 扩展点

### 添加新状态

1. 在 `island_state_stack.dart` 的 `IslandState` 枚举中添加
2. 在 `island_ui.dart` 的 `_targetSizeFor()` 中添加尺寸
3. 在 `_buildContent()` 中添加渲染方法
4. 决定是否需要受保护 → 添加到 `protectedStates`

```dart
// 示例：添加一个通知状态
enum IslandState {
  // ... 现有状态
  notification,  // 新增
}

// 在 _targetSizeFor 中
case IslandState.notification:
  return const Size(300, 80);

// 在 _buildContent 中
case IslandState.notification:
  return _buildNotification();

// 如果需要受保护
static const protectedStates = {
  // ... 现有
  IslandState.notification,
};
```

---

## 最佳实践

1. **使用栈 API**：所有状态操作通过 `push` / `pop` / `replaceTop` / `replaceBase`
2. **受保护状态**：需要用户交互的状态添加到 `protectedStates`
3. **自动消失**：使用 `_pushWithAutoDismiss()` 处理临时通知
4. **pop 验证**：`pop(expectedState)` 防止错误弹出
5. **clearToIdle**：完成/放弃等结束操作使用 `clearToIdle()`

---

## 问题排查

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 按钮无响应 | 栈操作未触发 `setState` | 检查 `_animateToState()` 是否被调用 |
| 完成后窗口异常 | 外部 payload 覆盖 | 确认状态在 `protectedStates` 中 |
| 状态不恢复 | `pop()` 的 expectedState 不匹配 | 检查栈顶状态是否符合预期 |
| 链接不消失 | `_autoDismissTimer` 问题 | 确认 `_pushWithAutoDismiss()` 参数正确 |
| 栈混乱 | replaceBase/replaceTop 使用错误 | 基础状态用 replaceBase，overlay 用 replaceTop |
