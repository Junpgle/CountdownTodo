# CountdownTodo MCP Server

这个本地 MCP Server 让 Claude、Codex、VS Code、Cursor 等 MCP Host 可以读取和操作 CountdownTodo 中的个人待办。

当前能力：

- 查询待办、读取详情和列出待办分类；
- 创建、修改、完成/恢复个人待办；
- 将个人待办软删除到回收站；
- 写入项目现有的 `op_logs`，继续由应用的 Uni-Sync 机制同步；
- 写入 `local_audit_logs`，保留 `AI (MCP)` 变更历史与回滚快照；
- 可选只读模式；
- 团队待办暂不暴露，避免在缺少当前用户身份时误读独立完成状态或绕过团队权限。

## 环境要求

- Node.js 22.13 或更高版本；
- CountdownTodo 已至少启动一次，并完成当前数据库迁移；
- 仅支持本地 `stdio`；MCP Server 本身不监听网络端口。AI Host 会把工具返回内容提供给其模型，仍需遵循所用 Host 和模型服务商的隐私策略。

## 安装与检查

```bash
cd /absolute/path/to/CountdownTodo/mcp-server
npm install
COUNTDOWN_TODO_DATABASE="/absolute/path/uni_sync_<username>.db" npm run check
```

数据库文件名是 `uni_sync_<当前登录用户名>.db`。常见查找方式：

```bash
# macOS
find "$HOME/Library" -name 'uni_sync_*.db' 2>/dev/null

# Linux
find "${XDG_DATA_HOME:-$HOME/.local/share}" -name 'uni_sync_*.db' 2>/dev/null
```

Windows PowerShell：

```powershell
Get-ChildItem "$env:APPDATA","$env:LOCALAPPDATA" -Filter "uni_sync_*.db" -Recurse -ErrorAction SilentlyContinue
```

路径必须指向数据库文件本身，不要指向目录。建议先退出 CountdownTodo，执行一次 `npm run check`，确认输出 `"schemaValid": true`。

## MCP Host 配置

所有路径都必须换成绝对路径。

VS Code 的 `.vscode/mcp.json`：

```json
{
  "servers": {
    "countdown-todo": {
      "type": "stdio",
      "command": "node",
      "args": ["/absolute/path/to/CountdownTodo/mcp-server/src/index.js"],
      "env": {
        "COUNTDOWN_TODO_DATABASE": "/absolute/path/uni_sync_<username>.db"
      }
    }
  }
}
```

使用 `mcpServers` 格式的客户端（例如 Claude Desktop、Cursor）：

```json
{
  "mcpServers": {
    "countdown-todo": {
      "command": "node",
      "args": ["/absolute/path/to/CountdownTodo/mcp-server/src/index.js"],
      "env": {
        "COUNTDOWN_TODO_DATABASE": "/absolute/path/uni_sync_<username>.db"
      }
    }
  }
}
```

建议首次接入先使用只读模式。若只希望 AI 查询数据，增加：

```json
"COUNTDOWN_TODO_MCP_READ_ONLY": "1"
```

只读模式不会向 MCP Host 注册任何写工具。

读写模式会直接修改本地 SQLite，并依靠 `op_logs` 在应用下次同步时上传。建议执行 MCP 写操作时关闭 CountdownTodo，或写入后先重启/刷新应用再继续手工编辑，避免应用内旧缓存覆盖外部修改；新建提醒也应打开一次应用，让客户端刷新通知计划。`delete_todo` 只会软删除到回收站，但仍建议让 MCP Host 在执行前要求人工确认。

## 可用工具

| 工具 | 作用 | 模式 |
| --- | --- | --- |
| `mcp_status` | 检查数据库连接与模式 | 只读 |
| `list_todo_groups` | 获取分类及 `groupId` | 只读 |
| `list_todos` | 按状态、关键词、分类、时间范围查询 | 只读 |
| `get_todo` | 按真实 `todoId` 获取详情 | 只读 |
| `create_todo` | 创建个人待办 | 写入 |
| `update_todo` | 修改标题、备注、分类、时间或提醒 | 写入 |
| `set_todo_completion` | 完成或恢复个人待办 | 写入 |
| `delete_todo` | 软删除到回收站 | 写入、破坏性提示 |

日期语义与 Flutter 客户端保持一致：`unscheduled` 不设置日期，`dateOnly` 表示某天内完成，`deadline` 表示明确截止时刻。循环待办必须设置首次发生日期；完成操作永远只作用于传入 `todoId` 对应的一期。

## 初期范围

- 目前只暴露个人待办；团队待办、倒计时、番茄钟、规划块和课程留待后续阶段。
- 当前实现面向 macOS、Windows 和 Linux 的本地 SQLite 数据库。Android、iOS 与 Web 数据需要后续增加带认证的远程 MCP 接入。
- MCP Server 不负责主动唤醒 Flutter UI、同步任务或通知调度；这些动作会在应用下次启动、刷新或同步时完成。

## 开发验证

```bash
npm run lint
npm test
```

测试会创建临时 SQLite 数据库，并通过官方 MCP Client 对 `stdio` 服务执行端到端调用，不读取或修改真实用户数据。
