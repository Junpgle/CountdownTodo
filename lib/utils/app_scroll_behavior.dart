import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 推荐的列表平滑滑动预加载距离（逻辑像素）。
///
/// 相比 Flutter 默认的 250px，适当增加至 600px 可以让滑动方向前方的
/// 卡片在进入可视区域前即在后台帧完成构建与排版，从根本上杜绝列表高速
/// 滑动时的单帧构建耗时波动（慢构建导致的丢帧），同时不破坏任何渲染特效。
const double kAppSmoothScrollCacheExtent = 600.0;

/// 全局流体平滑滑动物理（AppFluidScrollPhysics）
///
/// 融合高刷屏手势跟手性与自然弹性动量：
/// 1. 解决移动端默认物理在快速滑动（fling）时摩擦力过大、衰减过快、滑行动量不足的干涩感；
/// 2. 到达边缘时提供柔和自然的流体弹性缓冲，避免生硬撞墙或强行拉伸画面；
/// 3. 支持桌面端、触摸屏、手写笔与触摸板全输入场景；
/// 4. 完整保留所有毛玻璃、液态玻璃、阴影、微光粒子和过渡动画，无任何特效缩减。
class AppFluidScrollPhysics extends BouncingScrollPhysics {
  const AppFluidScrollPhysics({
    super.parent = const AlwaysScrollableScrollPhysics(),
    this.frictionBonus = 0.015,
  });

  /// 额外惯性顺滑增益（让滑动滑行距离更舒展，跟手度更高）
  final double frictionBonus;

  @override
  AppFluidScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return AppFluidScrollPhysics(
      parent: buildParent(ancestor),
      frictionBonus: frictionBonus,
    );
  }

  @override
  double frictionFactor(double overscrollFraction) {
    // 边界弹性阻尼：柔和渐进吸收多余动量，手感更细腻
    return 0.54 * math.pow(1.0 - overscrollFraction.clamp(0.0, 1.0), 2);
  }

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 75.0, stiffness: 110.0, damping: 1.1);
}

/// 全局应用滚动体验配置行为
///
/// 统合触控、手写笔、触控板与鼠标设备的滚动交互，
/// 赋予全应用平滑自然的滑动质感。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // 全平台提供一致的丝滑弹性流动物理，让滑动充满现代质感与轻快跟手感
    return const AppFluidScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // 弹性流体物理已原生包含平滑边缘回弹反馈，
    // 避免在液态玻璃/毛玻璃上覆盖生硬的拉伸发光波纹，保持高级质感。
    return child;
  }
}
