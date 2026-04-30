# CountDownTodo - 小米 Vela 快应用

运行在小米手环/手表上的快应用，提供待办事项、倒数日和课程表管理功能，支持与手机 Flutter App 通过蓝牙双向同步数据。

## 项目信息

| 项目 | 值 |
|------|-----|
| 包名 | `com.math_quiz.junpgle.com.math_quiz_app` |
| 版本 | 1.0.0 (versionCode: 1) |
| 最低平台版本 | 1000 |
| 设备类型 | watch |
| 框架 | Vela 快应用 (.ux 文件) |
| 构建工具 | aiot-toolkit ^2.0.5 |

## 功能特性

### 首页 (index.ux)
- 日期显示（中文格式：`4月3日 周三`）
- 同步状态胶囊指示器（空闲/同步中/成功/失败）
- 各模块摘要统计：待办未完成数、最近倒数日、今日课程数
- 一键同步所有数据到手机

### 待办事项 (todo.ux)
- 显示待办标题、描述、起止时间
- **进度条**：根据时间流逝计算完成进度，颜色分级：
  - 🔵 蓝色 (<50%)：早期
  - 🟡 橙色 (50%-74%)：正常
  - 🟠 深橙 (75%-99%)：警告
  - 🔴 红色 (≥100%)：逾期
  - 🟢 绿色：已完成
- **排序逻辑**：未完成在前 → 按进度降序（紧急优先）→ 截止时间升序
- 点击复选框切换完成状态，自动同步到手机

### 倒数日 (countdown.ux)
- 显示倒数日标题、剩余天数、目标日期
- 按剩余天数升序排列
- 支持删除倒数日

### 课程表 (course.ux)
- 显示今天/明天/后天三天的课程
- 每日分组，带日期和星期标题
- 课程卡片显示：时间、课程名、地点、教师、状态标签
- 状态检测（仅今天）：进行中（绿色条）、未开始（蓝色条）、已结束（灰色条）
- 支持 `date`（YYYY-MM-DD）和 `weekday`（1-7）两种匹配方式

### 设置 (settings.ux)
- 查看存储空间使用情况
- 分别清除待办/倒数日/课程缓存
- 一键清除所有数据
- 退出时触发垃圾回收

## 项目结构

```
CountDownTodo-band/
├── package.json                    # 依赖和脚本配置
├── sign/                           # 签名文件
│   ├── debug/                      # 调试签名 (private.pem, certificate.pem)
│   └── release/                    # 发布签名
├── docs/                           # Vela 快应用框架文档
├── build/                          # 编译输出 (自动生成)
├── dist/                           # 打包输出 (.rpk 文件)
└── src/
    ├── app.ux                      # 应用入口 (onCreate/onDestroy)
    ├── manifest.json               # 应用配置 (包名、权限、路由)
    ├── common/
    │   └── sync_service.js         # 手机同步服务 (367行)
    ├── pages/
    │   ├── index/index.ux          # 首页仪表盘 (478行)
    │   ├── todo/todo.ux            # 待办列表 (321行)
    │   ├── countdown/countdown.ux  # 倒数日列表 (286行)
    │   ├── course/course.ux        # 课程表 (353行)
    │   └── settings/settings.ux    # 设置/缓存管理 (354行)
    └── i18n/                       # 国际化文件
        ├── defaults.json
        ├── en.json
        └── zh-CN.json
```

## 各文件详细说明

### `src/app.ux`
应用生命周期入口。
- `onCreate()`: 初始化 `SyncService`
- `onDestroy()`: 调用 `SyncService.destroy()` 清理资源，执行 `global.runGC()` 垃圾回收

### `src/manifest.json`
应用配置文件。声明了包名、版本、设备类型、所需系统能力（router/prompt/storage/interconnect）、路由页面等。

### `src/common/sync_service.js`
核心同步引擎，负责与手机 Flutter App 的蓝牙通信。

**主要功能：**
- **连接管理**: 通过 `interconnect.instance()` 获取连接，监听 `onopen`/`onclose`/`onerror`
- **消息处理**: 解析 JSON 消息，支持分批数据传输（`batchNum`/`totalBatches`），10秒超时兜底
- **请求-响应机制** (`pendingSyncRequests`): 向手机发送 `request_sync` 后，等待手机推送数据回来，通过 Promise resolve 通知调用方，8秒超时
- **数据适配** (`adaptItem`): 将手机端字段名转换为手表端约定：
  - 倒数日: `target_time` → `targetDate`, `name` → `title`
  - 待办: `content` → `title`, `is_completed` → `status`, `created_date` → `startDate`, `due_date` → `endDate`, `remark` → `description`
  - 课程: `courseName` → `name`, `roomName` → `location`, `teacherName` → `teacher`, 数字时间 `HHMM` → 字符串 `"HH:MM"`
- **增量同步**: 仅同步 `updatedAt > lastSyncTime` 的数据
- **调试日志** (`sendDebugLog`): 向手机端发送调试信息
- **资源清理** (`destroy`): 清除所有批处理定时器和待处理请求，重置状态

### `src/pages/index/index.ux`
首页仪表盘。

**布局：**
- 顶部同步状态胶囊（圆点 + 文字）
- 标题区：CDT + 日期 + 同步按钮（同步中时旋转动画）
- 可滚动模块卡片列表：待办、倒数日、课程、设置

**数据加载：** 从 `sync_todo`/`sync_countdown`/`sync_course` 读取本地存储，计算统计信息。

### `src/pages/todo/todo.ux`
待办列表页。

**排序算法：**
```
1. 未完成在前，已完成在后
2. 未完成中按进度百分比降序（进度越高越紧急）
3. 进度相同时按截止时间升序（截止越早越优先）
```

**进度计算：**
```
progress = (当前时间 - 开始时间) / (截止时间 - 开始时间)
```
无截止时间时默认 24 小时窗口。

### `src/pages/countdown/countdown.ux`
倒数日列表页。支持数字时间戳和字符串日期两种格式，按剩余天数排序。

### `src/pages/course/course.ux`
课程表页。显示三天课程，使用 `<block if>` + `<div for>` 模式（非 `<list>`/`<list-item>`）以兼容手表渲染引擎。

### `src/pages/settings/settings.ux`
设置页。计算存储占用，提供逐项/全部清除功能。

## 数据存储

所有数据使用 `@system.storage` 持久化：

| 存储键 | 内容 | 格式 |
|--------|------|------|
| `sync_todo` | 待办列表 | JSON 数组 |
| `sync_countdown` | 倒数日列表 | JSON 数组 |
| `sync_course` | 课程列表 | JSON 数组 |
| `last_sync_time_todo` | 上次待办同步时间 | 时间戳字符串 |
| `last_sync_time_course` | 上次课程同步时间 | 时间戳字符串 |
| `last_sync_time_countdown` | 上次倒数日同步时间 | 时间戳字符串 |

## 数据流

```
手机 Flutter App
        │
        │  system.interconnect (蓝牙)
        ▼
  SyncService.js
  ├── onmessage() → 解析JSON → 批次重组 → adaptItem() → saveLocalData() (storage.set)
  ├── syncData() → 检查连接 → 按updatedAt过滤 → sendDataToPhone() → 更新lastSyncTime
  └── requestSyncFromPhone() → 发送 {action: 'request_sync'} → 手机响应

Storage (sync_todo, sync_countdown, sync_course)
        │
        │  storage.get()
        ▼
  各页面 (index.ux, todo.ux, countdown.ux, course.ux)
  ├── onInit() / onShow() → 从 storage 加载数据
  ├── 计算派生数据（进度、剩余天数、课程状态）
  └── 用户操作 → storage.set() → 触发同步回手机
```

**同步流程：**
1. 用户点击首页同步按钮
2. `SyncService.syncAll()` 依次处理三种数据类型
3. 对每种类型：
   - 向手机发送 `{type, action: 'request_sync'}` 请求数据，同时注册一个 Promise 等待响应
   - 手机收到请求后推送其数据到手表（通过 `connect.send()`）
   - 手表 `onmessage` 接收数据，调用 `replacePhoneData()` 保存数据
   - `replacePhoneData()` 保存完成后 resolve 对应的 Promise，`requestSyncFromPhone()` 返回成功
   - 若 8 秒内未收到手机响应，Promise 超时返回失败

## 系统 API

| API | 用途 |
|-----|------|
| `@system.storage` | `get()`/`set()`/`delete()` - 持久化键值存储 |
| `@system.router` | `push({uri})`/`back()` - 页面导航 |
| `@system.prompt` | `showToast({message, duration})` - 用户提示 |
| `@system.interconnect` | `instance()`/`send()`/`diagnosis()`/`getReadyState()` - 蓝牙通信 |
| `global.runGC()` | 手动触发垃圾回收 |
| `setTimeout()`/`clearTimeout()` | 防抖、状态自动重置、批处理超时 |
| 动态 `import()` | 懒加载 sync_service.js，减少内存占用 |

## 构建与运行

### 前置要求
- Node.js >= 8.10
- aiot-toolkit >= 2.0.5

### 安装依赖
```bash
npm install
```

### 开发模式
```bash
npm start          # 启动开发服务器 + 文件监听
```

### 构建
```bash
npm run build      # 构建调试版 .rpk
npm run release    # 构建发布版 .rpk (使用 release 签名)
```

输出文件：`dist/com.math_quiz.junpgle.com.math_quiz_app.debug.1.0.0.rpk`

### 代码检查
```bash
npm run lint       # ESLint 检查 .ux 和 .js 文件
```

### 安装到设备
将 `dist/` 下的 `.rpk` 文件传输到小米手环/手表进行安装。

## 与手机 App 同步配置

**关键要求：**
1. 快应用 `manifest.json` 中的 `package` 字段必须与手机 App 包名一致
2. 快应用必须使用与手机 App 相同的签名文件（`sign/debug/private.pem` 和 `certificate.pem`）
3. 手机 App 需实现 `system.interconnect` 通信接口

### 数据格式
```javascript
// 发送到手机 / 从手机接收
{
  "type": "countdown" | "todo" | "course",
  "data": [...],
  "timestamp": 1234567890
}

// 分批传输
{
  "type": "todo",
  "data": [...],
  "batchNum": 1,
  "totalBatches": 3
}
```

### 连接诊断
`connect.diagnosis()` 返回状态码：
- `0`: 连接成功
- `204`: 连接超时
- `1001`: 手机 App 未安装
- `1000`: 其他连接错误

## 内存优化

手表设备内存有限，本项目应用了以下优化策略：

| 优化项 | 实现位置 | 说明 |
|--------|----------|------|
| `static` 属性 | 所有页面模板 | 不变文本添加 `static`，减少动态绑定开销 |
| `onDestroy` 清理 | 所有页面 | 数据数组置 `null`，解除引用 |
| 定时器清理 | index.ux, todo.ux, sync_service.js | `onDestroy` 中 `clearTimeout` |
| 垃圾回收 | app.ux, settings.ux | 页面销毁时调用 `global.runGC()` |
| 动态导入 | todo.ux | `import().then()` 懒加载同步服务 |
| 原地修改 | todo.ux | 进度值直接修改对象属性，不创建新数组 |
| 非常量外提 | index.ux | `WEEKDAYS` 数组移出 `data`，避免 observer |
| 减少 console | 全局 | 移除冗余日志，仅保留错误捕获 |
| 避免 `<list>` | course.ux | 使用 `<block>` + `<div for>` 替代 `<list>`/`<list-item>`，避免手表渲染异常 |
| 避免单边描边 | course.ux | 用 `.status-bar` 色条替代 `border-left-*`，避免真机彩条问题 |

## 调试方法

### 开发调试
- `npm start` 启动开发服务器，文件变更自动重新编译
- `console.log()` 输出到 aiot-toolkit 控制台
- `console.debug()` 用于调试日志，发布构建时可通过 TerserPlugin 过滤

### 远程调试
- `SyncService.sendDebugLog('[模块] 信息')` 向手机 App 发送调试日志
- 检查 `system.storage` 中的数据确认同步状态

### 常见问题排查
1. **同步失败**: 检查包名和签名是否一致，使用 `connect.diagnosis()` 诊断连接
2. **页面不显示**: 检查 storage 中是否有数据，确认数据格式正确
3. **真机渲染异常**: 避免使用 `border-left-*`、`opacity`、动态 `border-color` 等手表不支持的 CSS
4. **内存溢出**: 检查是否有未清理的定时器，确认 `onDestroy` 中正确置空数据

## 注意事项

1. **手表端为只读展示**：数据在手机端创建和编辑，手表端仅展示和切换完成状态
2. **避免 setTimeout 延迟跳转**：logo 页如需等待异步结果，使用 `await` 而非 `setTimeout`
3. **图片优化**：如引入图片，尺寸不超过屏幕，大小不超过 200KB，优先使用本地图片
4. **减少 console 打印**：特别是长日志和 JSON 对象，严重影响性能
5. **CSS 兼容性**：手表渲染引擎不支持 `border-left-*`、`opacity` 等属性，使用 `background-color` 色条替代

## 配套手机 App

手机 Flutter App 位于上级目录 `../lib/`，实现了：
- 待办智能解析（AI 识别 / 大模型识别）
- 待办排序（与手表端一致的排序逻辑）
- 进度条显示
- 历史待办管理
- 与手表端的数据同步

## 许可证

MIT License
