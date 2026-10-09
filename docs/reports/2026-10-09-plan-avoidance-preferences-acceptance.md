# 第三轮补充：记住避让时间

日期：2026-10-09。用户要求上次勾选的避让时间在下一次默认选中。

## 结果

- 午休、午餐、晚餐的勾选状态及调整后的时间、自定义时段和勾选状态，以独立偏好键按账号保存在本机。
- 更改即保存，不依赖保存规划；关闭或取消编辑器后仍保留。取消勾选、删除自定义时段也会保存。
- 第一次使用默认不勾选。偏好恢复前暂不允许查找或修改避让；恢复后的查询同步给编辑器，参与推荐与手动保存检查。
- 切换账号重新加载，过期异步响应及旧账号的自定义弹窗结果不覆盖新账号。
- 读写队列保证快速修改后立即重开读取最后一次写入，写入使用调用时的快照。无效／损坏数据退回有效默认值；保存失败提示重试。
- 不新增日历事项，不修改规划记录结构，不改变默认五个推荐或展开动画。不包含云端偏好同步。

## 验收

```sh
flutter test --no-pub test/services/plan_availability_preferences_test.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/missed_plan_recovery_flow_test.dart --timeout 45s
flutter analyze --no-pub lib/services/plan_availability_preferences.dart lib/widgets/plan_availability_panel.dart test/services/plan_availability_preferences_test.dart test/widgets/plan_availability_panel_test.dart
/Users/junpgle/develop/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib/services/plan_availability_preferences.dart lib/widgets/plan_availability_panel.dart test/services/plan_availability_preferences_test.dart test/widgets/plan_availability_panel_test.dart
git -c core.fsmonitor=false diff --check
```

56项测试通过；新增6项偏好存储测试和3项界面测试，覆盖关闭重开、查询确实采用偏好、清空与移除、账号往返切换、修改预设与手动查询回调、顺序写入及损坏数据。回归保留共享编辑器、漏做重排和上一轮动画测试。

4文件静态分析无问题；4文件格式检查零变化；diff检查通过。
日志：`/tmp/plan-avoidance-memory-final-tests.log`、`/tmp/plan-avoidance-memory-final-analyze.log`。

未运行全仓测试、实机重启验收或发布构建。未提交、推送或部署。既有其他在途改动保持。
