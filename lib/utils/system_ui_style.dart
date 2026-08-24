import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_platform.dart';

/// CountDownTodo 的 Android 系统栏策略。
///
/// 页面背景延伸到系统栏后方，状态栏与手势导航条保持透明；三键导航由
/// Android 保留对比度保护层，避免导航键在滚动内容上失去可读性。
class AppSystemUiStyle {
  const AppSystemUiStyle._();

  static Future<void> enableEdgeToEdge({
    required Brightness initialBrightness,
  }) async {
    if (!AppPlatform.isAndroid) return;

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(forBrightness(initialBrightness));
  }

  static SystemUiOverlayStyle forBrightness(Brightness backgroundBrightness) {
    final iconBrightness = backgroundBrightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: backgroundBrightness,
      statusBarIconBrightness: iconBrightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: true,
    );
  }
}

/// 声明当前页面背后的明暗，让系统状态栏图标和导航提示条自动切换颜色。
class AppSystemUiRegion extends StatelessWidget {
  const AppSystemUiRegion({
    super.key,
    required this.backgroundBrightness,
    required this.child,
  });

  final Brightness backgroundBrightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isAndroid) return child;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUiStyle.forBrightness(backgroundBrightness),
      child: child,
    );
  }
}
