# Android 17 Xiaomi freeform 小窗：Flutter 内容被推到窗口下方

Status: fixed and verified on a Xiaomi Android 17 device on 2026-08-31.

## 适用范围

- Flutter Android 客户端。
- Android 17 / API 37。
- Xiaomi HyperOS 的自由窗（freeform）或悬浮小窗。
- Android 16 和正常全屏窗口不应改变现有行为。

## 现象

将 App 缩成小窗后，页面底部的悬浮按钮或底栏仍然可见，但主体内容消失：

- 首页只剩底栏，持续向上滑动后主体内容才出现。
- 个人时间轴初始看起来只有底部维度栏；过度上滑后能看到日期和统计内容。
- 专注栏/番茄钟可能只显示底部切换栏。
- Android 16 同样操作正常。

这个现象容易被误判为数据加载失败、懒加载没有触发，或者页面被底栏遮挡。实际上主体通常已经布局完成，只是被放到了小窗的可视区域之外。

## 根因

Android 35 及以后，Flutter Android embedding 会读取 `captionBar` 的 bounding rect，并将其底部并入顶部 `viewPadding`。Flutter 当前实现假设 caption bar 的矩形是相对于应用窗口的坐标：

```text
viewPaddingTop = max(viewPaddingTop, captionBarRect.bottom)
```

在部分 Xiaomi Android 17 freeform 场景中，系统把 caption bar 矩形按整块屏幕坐标上报，而不是按当前小窗坐标上报。结果是 Flutter 的 `MediaQuery` 可能得到接近整屏高度的：

```text
MediaQuery.padding.top
MediaQuery.viewPadding.top
```

CountDownTodo 中这些值会参与多个布局计算：

- `SafeArea` 的顶部避让。
- `floatingGlassTopBarHeight()` 的顶部栏高度。
- 个人时间轴的 sliver app bar 和初始内容位置。
- 首页顶部 header 的测量和列表 padding。

因此内容被整体排在小窗可视区域下方。底栏是固定在底部的独立控件，不依赖这个异常顶部 inset，所以仍然显示；向上过度滚动会把列表暂时拉回可视区域，这解释了“疯狂往上滑才出现”的表现。

Android 16 正常，是因为没有触发这条 Android 17 freeform + caption bar 坐标不一致的组合路径。

### 次要渲染问题

小窗切换时，Android 17 的自由窗合成器还可能对 `ShaderMask` 的 `BlendMode.dstIn` 和正在运行的渐隐动画处理不稳定。这会让已经正确布局的内容进一步表现为空白或透明，但它不是“内容被推到下面”的主要原因。

## 排查方法

在真实小窗中优先检查以下信息，而不是先改动业务数据或关闭懒加载：

1. 输出 `MediaQuery.size`、`padding.top`、`viewPadding.top`。
2. 如果顶部 inset 接近窗口高度，基本可以确认是 inset 坐标异常。
3. Android 原生侧检查 `Configuration.toString()` 中是否包含 `mWindowingMode=freeform`。
4. 对比 `WindowManager.currentWindowMetrics` 和 `maximumWindowMetrics`，确认当前窗口是否明显小于最大窗口。
5. 分别测试全屏、Android 16、Android 17 普通窗口和 Xiaomi Android 17 freeform，避免把平台专属问题扩散到所有窗口。

不要用“上滑后内容出现”证明懒加载有问题；这通常只是滚动偏移抵消了错误的顶部 inset。

## 当前修复策略

### Android 原生侧

`MainActivity.kt`：

- 通过 `isInMultiWindowMode`、freeform 配置字段和当前/最大 WindowMetrics 识别紧凑窗口。
- 在 `onConfigurationChanged`、`onMultiWindowModeChanged` 和 `onPostResume` 后延迟发送稳定的窗口信息。
- 尺寸稳定后请求 FlutterView 重新布局并刷新 renderer surface。
- Xiaomi Android 17 使用 `TextureView` 渲染路径，规避自由窗对默认 Surface 的重复缩放问题。

### Flutter 侧

`AndroidWindowRenderingPolicy`：

- 监听原生 `windowConfigurationChanged` 事件。
- Android 17 紧凑/自由窗中绕过容易丢失内容的顶部 `ShaderMask`。
- 番茄钟的 `FadingIndexedStack` 在小窗中直接绘制当前页面，避免 ticker 在窗口切换时停留在透明帧。
- 对异常超大的顶部 `padding`、`viewPadding` 和 `viewInsets` 设置 64dp 上限。
- 即使原生 freeform 回调晚到，只要发现异常超大顶部 inset，也执行布局兜底。

这项兜底只修正异常顶部值，不修改正常 Android 16、正常 Android 17 全屏窗口，也不关闭懒加载和滚动机制。底部 inset 保持系统原值，避免影响手势导航和底栏避让。

## 相关代码

- `android/app/src/main/kotlin/com/math_quiz/junpgle/com/math_quiz_app/MainActivity.kt`
  - `isCompactWindow()`
  - `windowRenderingInfo()`
  - `onPostResume()`
- `lib/services/android_window_rendering_policy.dart`
- `lib/main.dart` 的 `MaterialApp.builder`
- `lib/widgets/floating_glass_control.dart` 的顶部内容渐隐组件
- `lib/screens/pomodoro/widgets/fading_indexed_stack.dart`
- `test/widgets/floating_bottom_bar_test.dart`

## 验证记录

已完成：

- `flutter analyze`
- `flutter test test/widgets/floating_bottom_bar_test.dart`：31 项通过
- `flutter build apk --debug`
- Xiaomi Android 17 真机 freeform 小窗验证：首页、个人时间轴和专注栏内容均正常显示。

## 后续注意事项

- `android:resizeableActivity="true"` 和 `android.supports_size_changes` 只是声明窗口可调整，不能单独修复错误 inset。
- 透明系统栏或 edge-to-edge 也不能单独解决这个问题。
- 不要为了规避空白而全局关闭 ShaderMask、渐隐动画或懒加载；应只对 Android 17 紧凑自由窗启用兼容路径。
- 不要直接给 FlutterView 盲目增加 `fitsSystemWindows`，否则可能和 Flutter 自己的 `MediaQuery` inset 产生双重避让；如果未来改为原生 inset 修复，需要重新验证所有页面和键盘场景。
- 如果未来 Flutter Android embedding 修复 caption bar 坐标处理，应在 Android 16、Android 17 全屏和 Xiaomi freeform 三种环境回归后，再移除本地兼容策略。

## 参考

- [Xiaomi HyperOS 自由窗文档](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1593)
- [Android WindowInsets 官方文档](https://developer.android.com/develop/ui/views/layout/insets)
- [Flutter Android `FlutterViewDelegate` caption bar 处理](https://github.com/flutter/engine/blob/main/shell/platform/android/io/flutter/embedding/android/FlutterViewDelegate.java)
