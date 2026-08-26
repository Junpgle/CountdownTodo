import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'system_ui_style.dart';
import 'theme_color_tokens.dart';

const double _defaultScrollControlDisabledMaxHeightRatio = 9.0 / 16.0;

/// 显示可沉浸到系统导航栏后方、同时保证底部操作不被手势条遮挡的弹层。
///
/// Flutter 的 [showModalBottomSheet] 默认让弹层延伸到屏幕底部，但不会为
/// 底部系统栏增加安全间距。统一在内容外包一层仅处理底部的 [SafeArea]，
/// 弹层自身背景仍会绘制到导航栏后方。
Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio =
      _defaultScrollControlDisabledMaxHeightRatio,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  // App-owned sheet surfaces commonly draw their own handle. Do not inherit
  // the theme default here, otherwise the Material handle is rendered again
  // above the custom one. Callers that use the stock surface can opt in with
  // showDragHandle: true.
  bool? showDragHandle = false,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
  Brightness? navigationBarBackgroundBrightness,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: sheetAnimationStyle,
    requestFocus: requestFocus,
    builder: (sheetContext) {
      final bottomInset = MediaQuery.paddingOf(sheetContext).bottom;
      final needsTransparentSheetProtection =
          backgroundColor != null && backgroundColor.a == 0;
      final sheetBrightness = navigationBarBackgroundBrightness ??
          (backgroundColor != null && backgroundColor.a > 0
              ? ThemeData.estimateBrightnessForColor(backgroundColor)
              : Theme.of(sheetContext).brightness);

      return SizedBox(
        width: double.infinity,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppSystemUiStyle.forBrightness(sheetBrightness),
          // 即使业务内容没有声明宽度，也让标注覆盖整张弹层；否则系统在
          // 屏幕底部中央取样时可能落到标注之外，继续沿用下层页面的颜色。
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (needsTransparentSheetProtection && bottomInset > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: bottomInset,
                  child: ColoredBox(
                    color: Theme.of(sheetContext).colorScheme.surface,
                  ),
                ),
              SafeArea(
                top: false,
                left: false,
                right: false,
                child: builder(sheetContext),
              ),
            ],
          ),
        ),
      );
    },
  );
}

enum AppSnackBarType { info, success, warning, error }

class AppSnackBars {
  const AppSnackBars._();

  static void show(
    BuildContext context,
    String message, {
    AppSnackBarType type = AppSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (type) {
      AppSnackBarType.success => (
          colorScheme.cdtSuccessContainer,
          colorScheme.cdtOnSuccessContainer,
        ),
      AppSnackBarType.warning => (
          colorScheme.cdtWarningContainer,
          colorScheme.cdtOnWarningContainer,
        ),
      AppSnackBarType.error => (
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
        ),
      AppSnackBarType.info => (
          colorScheme.inverseSurface,
          colorScheme.onInverseSurface,
        ),
    };

    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: foreground)),
        backgroundColor: background,
        duration: duration,
        action: action,
      ),
    );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message, type: AppSnackBarType.success, duration: duration);
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message, type: AppSnackBarType.warning, duration: duration);
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message, type: AppSnackBarType.error, duration: duration);
  }
}

class AppDialogs {
  const AppDialogs._();

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    Widget? content,
    String cancelLabel = '取消',
    String confirmLabel = '确定',
    bool destructive = false,
    bool barrierDismissible = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: content ?? (message == null ? null : Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  static void showLoading(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  static void close(BuildContext context, {bool rootNavigator = true}) {
    final navigator = Navigator.of(context, rootNavigator: rootNavigator);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  static Future<T?> showAppBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool useSafeArea = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showAppModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (sheetContext) => DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: builder(sheetContext),
      ),
    );
  }
}
