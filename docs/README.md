# 项目文档目录

最后更新：`2026-05-24`

本目录收纳项目说明、功能设计、同步规则、排障报告和设计稿。仓库根目录只保留构建配置、入口说明和少量策略文件，避免再次堆积零散文档。

## 目录结构

- `ai/`：AI 待办助手、ML 规划和模型相关说明。
- `archive/`：历史路线图、草稿方案，仅作参考，不代表当前实现完全一致。
- `design/`：设计稿和视觉源文件。`.pptx`、`.psd` 默认受 `.gitignore` 影响，如需提交要显式 `git add -f`。
- `features/`：功能设计和当前实现说明。
- `private/`：测试账号等敏感或半敏感本地说明，不要在公开文档中复制其内容。
- `reports/`：问题排查、迁移、修复复盘。
- `sync/`：Uni-Sync、冲突处理、后端同步、协同设计说明。

## 当前优先维护文档

- `PROJECT_ARCHITECTURE.md`：当前应用结构、存储、同步、后端约束。
- `features/plan-blocks.md`：规划块当前实现、交互规则、番茄钟联动和剩余工作。
- `ai/todo-agent.md`：AI action 协议、上下文构建和入口说明。
- `sync/conflict-logic.md`：冲突中心规则、后端差异、番茄钟同步边界。
- `features/medal-recommendation.md`：勋章推荐实现和算法说明。
- `reports/version-management-fix.md`：版本管理修复复盘。
- `reports/conflict-resolution-efforts.md`：多端冲突反复出现问题排查记录。

## 根目录保留文档

- `Readme.md`：仓库总览和快速入口。
- `AGENTS.md`：编码代理使用的仓库规则。
- `CLAUDE.md`：Claude 使用的项目说明。
- `PRIVACY_POLICY.md`：隐私政策。

## 维护规则

- 新功能说明放到 `features/`。
- 排障和修复复盘放到 `reports/`。
- 同步、冲突、协同和后端策略放到 `sync/`。
- AI、LLM、ML 相关内容放到 `ai/`。
- 不要在根目录新增零散 `.md` 文件。
- 历史报告可以保留旧日期和旧结论，但应在文首或目录索引中标明它是历史记录。
