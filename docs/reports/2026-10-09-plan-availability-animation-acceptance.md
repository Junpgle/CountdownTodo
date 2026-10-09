# 第三轮补充：找可用时间展开动画

日期：2026-10-09。用户要求暂缓第四轮，先完善共享规划编辑器的展开动画。

## 改动

- “找可用时间”展开／收起使用260毫秒高度过渡与内容交叉淡入淡出，顶部对齐，箭头同步旋转。
- 反向点击沿当前进度过渡；输入、推荐数量和避让设置保留。展开操作不读取安排、不选择或保存规划。
- 漏做重新安排仍初始展开；系统减少动画设置直接切换内容，绕开零时长 AnimatedSize 布局异常。
- 复用现有共享编辑器；全天一屏、拖动新建及推荐规则保持现有行为。

## 验收

```sh
flutter test --no-pub test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart test/widgets/missed_plan_recovery_flow_test.dart
flutter analyze --no-pub lib/widgets/plan_availability_panel.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart
/Users/junpgle/develop/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib/widgets/plan_availability_panel.dart test/widgets/plan_availability_panel_test.dart test/widgets/plan_block_editor_sheet_test.dart
git -c core.fsmonitor=false diff --check
```

47项界面测试通过；3文件静态分析无问题；格式检查零变化；diff检查通过。
日志：`/tmp/plan-animation-final-tests.log`、`/tmp/plan-animation-final-analyze.log`。

新增动画验收检查展开／收起100毫秒的中间高度、固定标题位置、快速反向点击、输入保留、无额外查询／选用回调、初始展开及减少动画即时切换。回归包含默认五个候选、避让、保存复查、真实拖选入口、漏做重排及响应式布局。

未运行全仓测试、发布构建或原生设备验收。Web合成预览已启动编译，但浏览器停留资源加载阶段，未据此声称浏览器视觉验收通过。没有提交、推送或部署。
