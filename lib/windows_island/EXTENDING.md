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
├── island_config.dart        # 集中管理的常量和配置
├── island_channel.dart       # 与主应用的 IPC 通信
├── island_debug.dart         # 调试/测试页面
├── island_entry.dart         # 窗口入口点 (islandMain)
├── island_manager.dart       # 窗口生命周期管理
├── island_payload.dart       # 数据传输对象
├── island_reminder.dart      # 提醒服务
├── island_state_handler.dart # 可扩展的状态管理
├── island_ui.dart            # UI 组件和状态机（栈式管理）
└── island_win32.dart         # Win32 API 工具函数
```

### 数据流

```
HomeDashboard
  └── FloatWindowService.update()
        └── IslandDataProvider.buildPayload()
              └── IslandManager.sendStructuredPayload()
                    └── Island Window (island_entry.dart)
                          └── IslandUI (栈式状态机)
                                ├── _pushState()  // 入栈展示
                                ├── _popState()   // 出栈恢复
                                └── _replaceState() // 替换当前
```

---

## 用户交互流程

### 1. 时钟状态 (Idle)

**初始状态**：灵动岛显示当前时间

```
┌──────────────┐
│   14:30      │  ← 点击区域
└──────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 |
|----------|----------|--------|----------|
| 点击时钟 | 展开为 hoverWide (显示两侧信息) | `[idle] → [idle, hoverWide]` | 120x34 → 380x46 |
| 拖动时钟 | 移动窗口位置 | 不变 | 不变 |
| 悬停时钟 | 展开为 hoverWide (延迟100ms) | `[idle] → [idle, hoverWide]` | 120x34 → 380x46 |
| 鼠标离开 | 收回为 idle (延迟120ms) | `[idle, hoverWide] → [idle]` | 380x46 → 120x34 |

---

### 2. 专注状态 (Focusing)

**触发条件**：主应用发送 `state: 'focusing'` payload

```
┌──────────────┐
│  专注事项    │
│   25:00      │  ← 点击展开详情
└──────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击胶囊 | 展开为 stackedCard | `[focusing] → [focusing, stackedCard]` | 100x46 → 280x140 | - |
| 拖动胶囊 | 移动窗口位置 | 不变 | 不变 | - |
| 悬停 | 展开为 hoverWide | `[focusing] → [focusing, hoverWide]` | 100x46 → 380x46 | - |

**倒计时行为**：
- 每秒更新 `_remainingSecs`
- 通过 `_timeNotifier` 更新显示
- `endMs` 到达时 `_remainingSecs` 归零

---

### 3. 详情卡片 (StackedCard)

**触发条件**：点击专注状态的胶囊

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
| 点击卡片空白区域 | 收回为 focusing | `[focusing, stackedCard] → [focusing]` | 280x140 → 100x46 | - |
| 点击"完成" | 展开完成确认框 | `[focusing, stackedCard] → [focusing, stackedCard, finishConfirm]` | 280x140 → 260x130 | - |
| 点击"放弃" | 展开放弃确认框 | `[focusing, stackedCard] → [focusing, stackedCard, abandonConfirm]` | 280x140 → 260x130 | - |
| 拖动 | 移动窗口 | 不变 | 不变 | - |

---

### 4. 完成确认 (FinishConfirm)

**触发条件**：点击 stackedCard 的"完成"按钮

```
┌────────────────────────┐
│      确认完成?          │
│ 学习任务 | 25:00        │
│ ┌──────┐  ┌──────┐     │
│ │ 确认 │  │手滑了│     │
│ └──────┘  └──────┘     │
└────────────────────────┘
```

**受保护状态**：外部 payload 无法覆盖此状态

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"确认" | 1. 发送 `finish` action<br>2. 弹出确认框<br>3. 展示 finishFinal | `[finishConfirm] → [focusing, finishFinal]` | 260x130 | `finish` + `remainingSecs` |
| 点击"手滑了" | 返回 stackedCard | `[finishConfirm] → [focusing, stackedCard]` | 260x130 → 280x140 | - |

---

### 5. 放弃确认 (AbandonConfirm)

**触发条件**：点击 stackedCard 的"放弃"按钮

```
┌────────────────────────┐
│      确认放弃?          │
│ 学习任务 | 25:00        │
│ ┌──────┐  ┌──────┐     │
│ │手滑了│  │ 确认 │     │  ← 按钮位置相反
│ └──────┘  └──────┘     │
└────────────────────────┘
```

**受保护状态**：外部 payload 无法覆盖此状态

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"手滑了" | 返回 stackedCard | `[abandonConfirm] → [focusing, stackedCard]` | 260x130 → 280x140 | - |
| 点击"确认" | 1. 发送 `abandon` action<br>2. 清空栈回到 idle | `[abandonConfirm] → [idle]` | 260x130 → 120x34 | `abandon` |

---

### 6. 完成最终 (FinishFinal)

**触发条件**：完成确认后自动展示

```
┌────────────────────────┐
│      专注完成           │
│ 学习任务 | 25:00        │
│       ┌──────┐         │
│       │ 好的 │         │
│       └──────┘         │
└────────────────────────┘
```

**受保护状态**：外部 payload 无法覆盖此状态

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"好的" | 清空栈回到 idle | `[finishFinal] → [idle]` | 260x130 → 120x34 | - |

---

### 7. 复制链接 (CopiedLink)

**触发条件**：剪贴板检测到 URL，主应用发送 `copiedLinkData`

```
┌──────────────────────────────────────┐
│ 🔗 已复制: example.com    [打开] [✕] │
└──────────────────────────────────────┘
```

**受保护状态**：外部 payload 无法覆盖此状态
**自动消失**：10 秒后自动关闭

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"打开" | 1. 发送 `open_link` action<br>2. 关闭链接提示 | `[focusing, copiedLink] → [focusing]` | 340x46 → 100x46 | `open_link` + `url` |
| 点击"✕" | 关闭链接提示 | `[focusing, copiedLink] → [focusing]` | 340x46 → 100x46 | - |
| 等待10秒 | 自动关闭 | `[focusing, copiedLink] → [focusing]` | 340x46 → 100x46 | - |
| 拖动 | 移动窗口 | 不变 | 不变 | - |

**时序图**：
```
剪贴板检测URL
  │
  ├─→ FloatWindowService._showCopiedLinkIsland()
  │     │
  │     └─→ IslandManager.sendStructuredPayload({state: 'copied_link', copiedLinkData: {...}})
  │           │
  │           └─→ IslandUI._pushState(copiedLink, autoDismiss: 10s)
  │
  ├─→ 用户点击"打开"
  │     │
  │     ├─→ widget.onAction('open_link', 0, url)
  │     │     │
  │     │     └─→ FloatWindowService._refreshIslandAfterLinkOpened()
  │     │
  │     └─→ _popState(copiedLink)
  │
  └─→ 10秒后自动 pop
```

---

### 8. 提醒胶囊 (ReminderCapsule)

**触发条件**：岛内提醒检查发现待提醒事项

```
┌────────────────────────┐
│ 📝 会议 15min          │  ← 点击展开详情
└────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击胶囊 | 展开为 reminderPopup | `[reminderCapsule] → [reminderPopup]` | 160x46 → 320x150+ | - |
| 拖动 | 移动窗口 | 不变 | 不变 | - |

---

### 9. 提醒弹窗 (ReminderPopup)

**触发条件**：点击 reminderCapsule 或收到强提醒

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

**受保护状态**：外部 payload 无法覆盖此状态

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 点击"好的" | 1. 发送 `reminder_ok`<br>2. 关闭弹窗 | `[reminderPopup] → [focusing/idle]` | 恢复原大小 | `reminder_ok` |
| 点击"稍后提醒" | 1. 发送 `remind_later`<br>2. 关闭弹窗<br>3. 主应用显示选择框 | `[reminderPopup] → [focusing/idle]` | 恢复原大小 | `remind_later` |
| 拖动 | 移动窗口 | 不变 | 不变 | - |

---

### 10. 双胶囊提醒 (ReminderSplit)

**触发条件**：专注状态下收到提醒

```
┌──────────────────────────────────────────────┐
│  🎯 25:00          📝 会议 15min             │  ← 紧凑模式
└──────────────────────────────────────────────┘

点击右侧胶囊后：

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
| 点击左侧胶囊 | 展开/收起专注详情 | `[reminderSplit]` 不变 | 480x46 ↔ 320x300 | - |
| 点击右侧胶囊 | 展开/收起提醒详情 | `[reminderSplit]` 不变 | 480x46 ↔ 320x300 | - |
| 展开后点"好的" | 确认提醒，收起 | `[reminderSplit] → [focusing]` | 320x300 → 100x46 | `reminder_ok` |
| 展开后点"稍后提醒" | 稍后提醒，收起 | `[reminderSplit] → [focusing]` | 320x300 → 100x46 | `remind_later` |

---

### 11. Hover 展开 (HoverWide)

**触发条件**：鼠标悬停在 idle 或 focusing 状态上

```
┌──────────────────────────────────────────────────────────────────────────┐
│ 待办事项              │ 14:30 │              13:00 课程                   │
└──────────────────────────────────────────────────────────────────────────┘
```

| 用户操作 | 预期行为 | 栈变化 | 窗口大小 | 发送 Action |
|----------|----------|--------|----------|-------------|
| 鼠标悬停 | 展开为 hoverWide (延迟100ms) | `[idle] → [idle, hoverWide]` | 120x34 → 380x46 | - |
| 鼠标离开 | 收回 (延迟120ms) | `[idle, hoverWide] → [idle]` | 380x46 → 120x34 | - |
| 点击空白区域 | 如果是专注，展开 stackedCard | `[focusing, hoverWide] → [focusing, stackedCard]` | 380x46 → 280x140 | - |
| 拖动 | 移动窗口 | 不变 | 不变 | - |

---

### 状态转换总览

```
                          ┌─────────────────┐
                          │     idle        │
                          └────────┬────────┘
                                   │ 点击/悬停
                                   ▼
                          ┌─────────────────┐
                          │   hoverWide     │
                          └────────┬────────┘
                                   │ 离开/点击
                                   ▼
        ┌────────────────────────────────────────────────┐
        │                    focusing                    │
        └───────────────────────┬────────────────────────┘
                                │ 点击
                                ▼
        ┌────────────────────────────────────────────────┐
        │                  stackedCard                   │
        └───────┬────────────────────────────┬───────────┘
                │ 点击完成                    │ 点击放弃
                ▼                            ▼
        ┌───────────────┐            ┌───────────────┐
        │ finishConfirm │            │ abandonConfirm│
        └───────┬───────┘            └───────┬───────┘
                │ 确认                       │ 确认
                ▼                            ▼
        ┌───────────────┐            ┌───────────────┐
        │ finishFinal   │            │     idle      │
        └───────┬───────┘            └───────────────┘
                │ 点击好的
                ▼
        ┌───────────────┐
        │     idle      │
        └───────────────┘
```

---

### 中断场景

| 场景 | 当前状态 | 中断来源 | 行为 |
|------|----------|----------|------|
| 专注中复制链接 | focusing | 剪贴板 | push(copiedLink)，10秒后自动恢复 |
| 专注中收到提醒 | focusing | 提醒检查 | replace(reminderSplit)，用户确认后恢复 |
| 完成确认中复制链接 | finishConfirm | 剪贴板 | **被阻止**，finishConfirm 是受保护状态 |
| 弹窗中收到新payload | reminderPopup | 主应用 | **被阻止**，reminderPopup 是受保护状态 |

---

## 核心概念

### 栈式状态管理

```dart
// 栈操作 API
_pushState(state, payload, {autoDismiss})  // 入栈展示
_popState(expectedState)                    // 出栈恢复
_replaceState(state, payload)              // 替换栈顶
_clearToIdle()                             // 清空回 idle
```

### 受保护状态

```dart
final protectedStates = [
  IslandState.finishConfirm,   // 完成确认 - 用户必须选择
  IslandState.abandonConfirm,  // 放弃确认 - 用户必须选择
  IslandState.finishFinal,     // 完成最终 - 用户点击后消失
  IslandState.copiedLink,      // 复制链接 - 超时或用户关闭
  IslandState.reminderPopup,   // 提醒弹窗 - 用户确认后消失
];
```

### 数据载荷结构

```dart
{
  'state': 'focusing',           // 目标状态
  'focusData': {
    'title': '任务名称',
    'endMs': 1234567890,
    'timeLabel': '25:00',
    'isCountdown': true,
    'tags': ['学习'],
    'syncMode': 'local',
  },
  'reminderPopupData': {
    'type': 'todo',
    'title': '会议',
    'subtitle': '301会议室',
    'minutesUntil': 15,
    'isEnding': false,
    'itemId': 'unique-id',
  },
  'copiedLinkData': {
    'url': 'https://example.com',
    'displayUrl': 'example.com',
  },
}
```

### 操作列表

| 操作 | 说明 | 触发时机 | 数据 |
|------|------|----------|------|
| `finish` | 专注完成 | 用户确认完成 | remainingSecs |
| `abandon` | 放弃专注 | 用户确认放弃 | 0 |
| `reminder_ok` | 确认提醒 | 点击"好的" | - |
| `remind_later` | 稍后提醒 | 点击"稍后提醒" | - |
| `open_link` | 打开链接 | 点击"打开" | url |

---

## 扩展点

### 添加新状态

1. 在 `island_ui.dart` 的 `IslandState` 枚举中添加
2. 在 `_computeState()` 中添加映射
3. 在 `_buildContent()` 中添加渲染
4. 在 `_targetSizeFor()` 中添加尺寸
5. 决定是否需要受保护

### 添加新的受保护状态

```dart
final protectedStates = [
  // ... 现有状态
  IslandState.myNewProtectedState,
];
```

---

## 最佳实践

1. **使用栈式 API**：所有临时状态用 `_pushState` / `_popState`
2. **受保护状态**：需要用户交互的状态添加到 `protectedStates`
3. **自动消失**：临时通知使用 `autoDismiss` 参数
4. **错误处理**：栈操作用 try-catch 包裹

---

## 问题排查

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 按钮无响应 | `setState` 未调用 | 确保 `_pushState` 正常执行 |
| 完成后窗口异常 | 被外部 payload 覆盖 | 添加到受保护状态列表 |
| 链接提示不消失 | `autoDismiss` 未设置 | 检查 `_pushState` 参数 |
| 状态混乱 | 栈操作异常 | 检查 `_popState` 的 expectedState 匹配 |
