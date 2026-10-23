# 第34轮验收：账单列表汇总层级与历史分类回退

日期：2026-10-23（北京时间）
状态：实施与验收已完成，待用户确认

## 实施结果

- 单日普通浏览时，日期行保留日期与账单笔数；净支出和已发生收入不再与底部筛选总计重复。未来计划支出摘要仍在日期行显示，计划金额仍保留在底部汇总。
- 多日浏览保留每日小计，并继续显示全筛选范围总计。
- 进入选择模式后继续区分整日金额和已选账单总计；提交选择后继续显示所选总计。
- 已删除分类的历史账单仍能通过原分类 UUID 筛选；列表和详情显示“分类已删除或不可用”，不误标为“未分类”。
- 纠正了未来收入摘要测试的定位方式：验证其位于底部汇总卡片，不再依赖过时的独立标签。

涉及文件：`lib/features/finance/widgets/finance_widgets.dart`、`test/features/finance/finance_management_screens_test.dart`、本轮方案与验收文档，以及下方三张验收图。

## 验收结果

| 检查 | 结果 |
| --- | --- |
| `flutter test test/features/finance/finance_management_screens_test.dart` | 130 项通过，3 项跳过 |
| `flutter test test/features/finance/` | 630 项通过，5 项跳过 |
| 受影响 Dart 文件 `flutter analyze` | 无问题 |
| 全量 `flutter analyze` | 无错误；1 条既有 info：`lib/windows_island/island_ui.dart:5:8` 的 `unnecessary_import` |
| `dart format --output=none --set-exit-if-changed`（本轮两个 Dart 文件） | 通过，0 个文件需要格式化 |
| `flutter build web --release` | 通过 |
| 全量 `flutter test` | 3,149 项通过、5 项跳过、7 项 DST 相关失败；失败项来自当前 `Asia/Shanghai` 无夏令时环境下的既有时区断言，本轮未改这些语义 |
| 5 个相关 DST 测试文件以 `TZ=America/New_York` 重跑 | 15 项全部通过 |
| `git diff --check` | 通过 |

全量测试中的 7 项失败分别涉及个人时间线日／周边界、日期搜索回拨日范围、时间线财务回拨／春季切换范围、日历日期范围 DST，以及跨日时间日志春季切换拆分。切换到有夏令时的 `America/New_York` 时区后，相关 15 项断言通过。

## 界面检查与证据范围

我用本地 Release Web 预览直接渲染了 `FinanceLedgerPanel` 和账单详情组件，视口为 390 × 844，分别核对单日汇总、多日小计、已删除分类历史账单。浏览器截图已在本轮对话中展示：单日日期行不再重复底部净支出；多日日期行分别显示 ¥10.00 与 ¥5.00，而筛选总计为 ¥15.00；历史账单行显示“分类已删除或不可用”。

以下三张保存的验收图是相同组件和合成数据的 Flutter Widget 渲染，手机视口为 390 × 844，便于随报告查看。它们不是设备截图；测试渲染环境缺少账单自定义图标所用的 emoji 字形，因此图标显示为方框，文字、金额和布局仍可检查。

![单日账单列表与汇总](/Users/junpgle/StudioProjects/CountdownTodo/docs/reports/evidence/round-34/finance-ledger-single-day-phone.png)

![多日账单小计与筛选总计](/Users/junpgle/StudioProjects/CountdownTodo/docs/reports/evidence/round-34/finance-ledger-multi-day-phone.png)

![已删除分类的历史账单回退](/Users/junpgle/StudioProjects/CountdownTodo/docs/reports/evidence/round-34/finance-ledger-deleted-category-phone.png)

预览使用合成账单数据，不涉及登录、真实账户或用户财务记录。这些是本地浏览器中的真实组件渲染截图，不是真机截图，也不代表登录后账户页面。由于应用账单页需要登录，本轮未使用用户账户数据。

## 提交与工作区范围

本轮只提交账单列表实现、回归测试、验收图片、方案和本验收报告。既有 Android 课程提醒改动保持未暂存、未提交；未推送、发布或部署。
