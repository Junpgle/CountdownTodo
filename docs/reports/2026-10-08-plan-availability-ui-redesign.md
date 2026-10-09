# 第二轮界面重设计验收

用户反馈“这个 UI 很丑，你再重新设计一下”，按该指令直接重设计既有规划编辑器和可用时间面板。此为第二轮调整，尚未开始第三轮。

## 改动

- 点击新增、拖选新增和编辑统一使用 `showPlanBlockEditorSheet`；桌面最大宽度 680，移动端随可用宽度布局。使用应用已有 `OptionalLiquidGlassSheet`，保留动态主题和玻璃开关，不改全局弹层。
- 标题、待办、日期及时间形成主层次；时间改为大字块。窄屏隐藏装饰图标，避免标题被操作按钮挤断。
- 查找条件集中到独立面板，快捷时长与自定义输入统一样式；推荐改为可整块点击的卡片，选用后显示勾选及高亮。
- 来源覆盖、截止和占用明细放在推荐之后，仍保留失败提示及显式应用内查找选择。
- 备注、番茄和提醒统一填充式输入；宽屏三列、窄屏纵向。AI 入口改为次级文字按钮。
- 常规高度固定标题和保存栏，只滚动表单；键盘、大字体和横屏导致高度不足时，整个内容可滚动。编辑时跳过／删除收进“更多操作”；新增关闭按钮。
- 表单以动态主题的半透明表面色提高玻璃模式下的内容对比度，减少背后文字干扰。

推荐算法、占用规则、条件保存、专注启动服务和账号校验未改。本次未增加依赖、权限、字段或后端变更。

## 自动验收

最终 9 个聚焦及回归文件：**91 项全部通过**。覆盖推荐、隔离 SQLite 保存、取消零写入、失效拒绝、重复操作、专注重试，以及完整规划日视图的点击／拖选／编辑三个真实入口。

布局组合同时覆盖标准／玻璃：320×640 + 字体1.6 + 键盘260；390×844 + 字体2；720×360 + 字体1.6 + 键盘130；1280×900 + 字体2。控件可达，无布局溢出。

执行：

```sh
flutter test test/services/plan_availability_service_test.dart test/services/plan_availability_repository_test.dart test/services/device_calendar_refresh_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart test/services/schedule_conflict_service_test.dart test/services/calendar_sync_service_test.dart test/models/todo_time_semantics_test.dart test/widgets/app_dialogs_test.dart --reporter expanded
flutter analyze lib/widgets/plan_availability_panel.dart lib/widgets/plan_block_editor_sheet.dart lib/screens/todo_plan_screen.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/plan_availability_panel_test.dart
dart format --output=none --set-exit-if-changed lib/widgets/plan_availability_panel.dart lib/widgets/plan_block_editor_sheet.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/plan_availability_panel_test.dart
git -c core.fsmonitor=false diff --check
```

分析无问题；格式无新增变化；差异空白检查通过。未跑仓库全量测试／全量分析或发布构建，未 commit、push、部署。

## 可见验收

使用正式编辑器和正式共享路由，数据仅为合成样本；预览保存仅留在内存。SQLite 持久化另由上述自动测试验证，不将浏览器演示当作原生通知／日历验收。

![桌面表单](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-availability/ui-redesign-desktop-form.png)

![推荐选中状态](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-availability/ui-redesign-desktop-selected.png)

![深色窄屏玻璃模式](/Users/junpgle/.codex/visualizations/2026/10/07/01a1159f-0bbb-7b42-a276-742283415ffd/plan-availability/ui-redesign-mobile-dark-glass.png)

实际浏览器验证：320×640 深色玻璃、字体1.6时查询45分钟，选用10:00–10:45后关闭仍未保存；恢复桌面、浅色玻璃和常规字体后重新选用同一时段，显式保存显示“已保存1次”。临时 viewport 已恢复。

日志与截图保存在同一证据目录。最终预览地址为 `http://127.0.0.1:8950/`。Android/iOS 实机视觉、系统日历与通知未验证。

用户于2026-10-08确认“可以，继续下一轮”，第二轮外观及操作验收通过。[第三轮方案](../proposals/2026-10-08-missed-plan-recovery.md)已提出，尚待批准实施。
