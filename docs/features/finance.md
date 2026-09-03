# 个人记账

当前状态：本地 MVP、第二阶段预算管理、第三阶段个人云同步、第四阶段自动化、
第五阶段分期账单和第六阶段贷款管理已实现。

## 产品边界

记账是个人数据域，当前支持支出、收入和退款。金额以人民币分的整数保存，
避免浮点误差；统计按本地账单日期计算。账单不参与团队协作，也不携带
`team_uuid`。

第一版只把微信、支付宝、银行卡、现金、信用卡等作为付款方式记录，不计算
账户余额，也不提供银行自动同步。

第二阶段增加按月预算：可以为整月全部支出设置总预算，也可以为单个支出分类
设置分类预算；预算进度按已保存的账单实时计算，超支会单独标记。

第四阶段增加预算和自动化闭环：预算达到 80% 或超支时可发送系统通知；周期账单
支持每月/每年重复、月末日期自动校准、提前提醒和到期自动记账；快捷模板可以
一键填充金额、类型、分类、付款方式和备注。自动生成使用“规则 UUID + 周期键”
在 SQLite 事务中幂等落库，同一周期不会重复记账；应用恢复运行时会按时间顺序
补齐最近 12 个遗漏周期；无生成标记的新规则只生成当前周期，避免历史开始日期
一次性灌入大量账单。桌面端在记账首页使用
`Ctrl/Cmd + Shift + N` 打开快速录入。

第五阶段支持在录入支出时开启分期，设置 2-60 个月。应用会从账单日期开始按月
生成多笔交易，短月自动使用当月最后一天；金额始终按“分”精确分摊，不能整除
时前几期各多 1 分，确保各期合计与原始总额一致。分期交易共享分期组标识，编辑
分期时会同步重算整组，列表、CSV、回收站支持查看和操作整组分期。

第六阶段增加独立的贷款负债管理：记录本金、出借方、年利率、期限、还款日和
还款方式，支持等额本息与等额本金，并自动生成每期本金、利息、应还金额和剩余
本金。贷款本金不计入收入；标记某期已还时，只将该期利息写入“贷款利息”支出，
本金通过剩余负债下降体现，避免把借款和还款本金重复计入收支统计。

支出账单可从列表菜单直接发起“原单退款”。退款会保存原账单关联，
默认带入原单分类、付款方式和剩余可退金额；用户可改为任意正数完成
部分退款，也可对同一原单多次退款。本地保存、备份导入和云端合并都会
校验累计退款不得超过原金额；存在有效退款时，原单不能被删除、改成
其他类型或把金额调低到已退金额以下。

第三阶段接入个人云同步：记账通过现有 `/api/sync` 认证和事务边界传输，使用独立
的 `finance_v1` 能力声明、个人水位线和增量游标。八类记账记录均按
`updated_at`、再按 `version` 执行 LWW；删除使用软删除墓碑，服务端发现过期或
非法入参时返回冲突并要求客户端全量修复。记账数据只按 `user_id` 隔离，不进入
团队数据，也不上传系统默认分类/付款方式。旧服务端未声明 `finance_v1` 时，
客户端不会合并返回空字段，也不会前移记账水位线；请求期间本地发生修改时同样
不会跳过该修改。V48 起基础六张表增加 `pending_sync`；V51 新增的贷款主表和还款明细表也使用同一机制：本地新增、编辑、删除和导入先标记待同步，服务端确认接受后才清除；网络失败、冲突和请求期间的并发修改会
保留标记，因此增量上传不再依赖本机时间是否晚于云端游标。
记账云同步按账号默认关闭，必须在“记账设置”中显式开启；关闭会停止后续同步并
忽略已在途请求的记账 ACK 和快照，但不会取消待办、习惯等共用同步请求，
也不会自动删除服务器上已经存在的历史副本。

## 代码结构

- `lib/features/finance/models/finance_models.dart`：交易、预算、周期规则、模板、分类、付款方式、贷款和汇总模型。
- `lib/features/finance/services/finance_storage.dart`：SQLite 表、系统默认数据、软删除、周期账单/贷款计划生成和备份导入导出。
- `lib/features/finance/services/finance_sync_service.dart`：个人记账同步请求快照、能力门控、增量游标和竞态保护。
- `lib/features/finance/services/finance_automation_service.dart`：重复日期计算、周期提醒、自动生成和预算阈值通知。
- `lib/features/finance/services/finance_repository.dart`：领域门面、金额解析和 CSV 导出。
- `lib/features/finance/screens/finance_home_screen.dart`：月份概览、账单列表、筛选和导航。
- `lib/features/finance/screens/finance_entry_screen.dart`：快速记一笔和编辑账单。
- `lib/features/finance/screens/finance_settings_screen.dart`：自定义分类和付款方式。
- `lib/features/finance/screens/finance_automation_screen.dart`：周期账单和快捷模板管理。
- `lib/features/finance/screens/finance_trash_screen.dart`：删除账单、预算、周期账单和模板恢复。
- `lib/features/finance/screens/finance_budget_screen.dart`：按月查看预算进度。
- `lib/features/finance/screens/finance_budget_entry_screen.dart`：新增和编辑预算。
- `lib/features/finance/screens/finance_loan_screen.dart`：贷款负债概览、详情和还款计划。
- `lib/features/finance/screens/finance_loan_entry_screen.dart`：新增和编辑贷款。

## 数据库

客户端 SQLite schema v51 新增/扩展：

- `finance_transactions`
- `finance_categories`
- `finance_payment_methods`
- `finance_budgets`
- `finance_recurring_rules`
- `finance_entry_templates`
- `finance_loans`
- `finance_loan_installments`

八张表均包含 `pending_sync`。从旧版本升级时，已有个人记录会安全排队一次，待
服务端确认后清除；系统默认分类和付款方式不会进入待同步队列。

系统分类和系统付款方式使用稳定 ID。历史分类和付款方式只能归档，不能物理
删除，以免历史账单失去可读性。退款归入支出分类域，升级时会将旧版绑定在
收入分类的退款迁移到系统“退款”分类并排队同步。

## 入口和备份

首页悬浮操作提供“记一笔”，侧边栏提供“记账”入口。数据导出/导入支持
`finance` 数据块，包含交易、预算、分类、付款方式、贷款和还款明细；CSV 导出用于
当前月份的人工分析。JSON 备份导入使用单个 SQLite 事务：任一写入失败时整批回滚；
系统分类/付款方式不接受备份覆盖，旧版数字交易类型仍可导入，没有活动父贷款的
孤立还款计划会被跳过。JSON 备份同时包含周期规则和快捷模板；预算页面可从记账页
右上角进入，贷款页面可从记账页右上角“贷款”进入，自动化页面可从“自动化与快捷模板”进入。

## 服务端同步实现

- Alibaba 服务端研发实现位于外部 checkout 的
  `CDT-server/debug/services/financeSync.js`、`debug/routes/sync.js` 和
  `debug/db/init.js`；生产 `math_quiz_backend/` 与仓库内 Cloudflare Worker
  兼容路径保持不变。
- 分期字段位于 `finance_transactions` 的
  `installment_group_uuid`、`installment_index`、`installment_count` 和
  `installment_total_minor`；旧服务端仍可保存每一期普通交易，但不会返回分期
  关系，正式服务接入这些字段前跨设备展示可能退化为独立账单。
- 贷款字段位于 `finance_loans` 和 `finance_loan_installments`；客户端会把贷款主表、
  还款状态和关联的利息账单一起同步。当前新增协议已写入 Alibaba debug 服务端，
  生产 `math_quiz_backend/` 尚未部署或重启。
- 客户端同步只传递结构化账单字段；图片附件（如果未来加入）默认只保存在本机，
  不应直接把本地路径上传到云端。
