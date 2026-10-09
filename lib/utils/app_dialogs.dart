import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../services/liquid_glass_effect_service.dart';
import 'semester_week_context.dart';
import 'system_ui_style.dart';
import 'theme_color_tokens.dart';

const double _defaultScrollControlDisabledMaxHeightRatio = 9.0 / 16.0;
const double _appGlassDialogRadius = 28;

Widget _appDialogButtonBackground(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => child ?? const SizedBox.shrink();

ThemeData _appDialogContentTheme(ThemeData theme) {
  final scheme = theme.colorScheme;
  final flatButtonStyle = ButtonStyle(
    backgroundBuilder: _appDialogButtonBackground,
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: const WidgetStatePropertyAll(BorderSide.none),
  );
  final dialogTheme = theme.dialogTheme.copyWith(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_appGlassDialogRadius),
      side: BorderSide.none,
    ),
  );
  final datePickerTheme = theme.datePickerTheme.copyWith(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_appGlassDialogRadius),
    ),
    rangePickerShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_appGlassDialogRadius),
    ),
  );
  final timePickerTheme = theme.timePickerTheme.copyWith(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_appGlassDialogRadius),
    ),
  );

  return theme.copyWith(
    dialogTheme: dialogTheme,
    datePickerTheme: datePickerTheme,
    timePickerTheme: timePickerTheme,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: flatButtonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: flatButtonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
        backgroundColor: WidgetStatePropertyAll(scheme.primary),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: flatButtonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.primary),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: flatButtonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.primary),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: flatButtonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
        shape: const WidgetStatePropertyAll(CircleBorder()),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: flatButtonStyle.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.secondaryContainer
              : scheme.surfaceContainerLow,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
      ),
    ),
  );
}

Widget _applyAppDialogTheme(BuildContext context, Widget dialog) {
  final configuration = LiquidGlassEffectService.configuration;
  if (!configuration.enabled) return dialog;

  final theme = Theme.of(context);
  return Theme(data: _appDialogContentTheme(theme), child: dialog);
}

/// Shows a dialog with the shared app theme and route behavior.
///
/// Route behavior and the dialog's intrinsic Material layout stay identical
/// to [showDialog]. When Liquid Glass is enabled, shared action-button styles
/// are applied while the app's dynamic dialog surface and sizing stay intact.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle: animationStyle,
    builder: (dialogContext) {
      return _applyAppDialogTheme(dialogContext, builder(dialogContext));
    },
  );
}

/// Routes custom dialog transitions while applying the shared overlay theme.
Future<T?> showAppGeneralDialog<T extends Object?>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  bool barrierDismissible = false,
  String? barrierLabel,
  Color barrierColor = const Color(0x80000000),
  Duration transitionDuration = const Duration(milliseconds: 200),
  RouteTransitionsBuilder? transitionBuilder,
  bool useRootNavigator = true,
  bool fullscreenDialog = false,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  return showGeneralDialog<T>(
    context: context,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _applyAppDialogTheme(
        dialogContext,
        pageBuilder(dialogContext, animation, secondaryAnimation),
      );
    },
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    transitionDuration: transitionDuration,
    transitionBuilder: transitionBuilder,
    useRootNavigator: useRootNavigator,
    fullscreenDialog: fullscreenDialog,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    requestFocus: requestFocus,
  );
}

/// Shows a date picker with the shared app theme and native Material sizing.
///
/// Date selection, localization, range constraints, and any caller-provided
/// builder remain delegated to Flutter's [showDatePicker].
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
  SelectableDayPredicate? selectableDayPredicate,
  String? helpText,
  String? cancelText,
  String? confirmText,
  Locale? locale,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  TextDirection? textDirection,
  TransitionBuilder? builder,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
  String? errorFormatText,
  String? errorInvalidText,
  String? fieldHintText,
  String? fieldLabelText,
  TextInputType? keyboardType,
  Offset? anchorPoint,
  ValueChanged<DatePickerEntryMode>? onDatePickerModeChange,
  Icon? switchToInputEntryModeIcon,
  Icon? switchToCalendarEntryModeIcon,
  CalendarDelegate<DateTime> calendarDelegate =
      const GregorianCalendarDelegate(),
  SemesterWeekContext? semesterWeekContext,
}) {
  final effectiveCalendarDelegate = semesterWeekContext == null
      ? calendarDelegate
      : SemesterWeekCalendarDelegate(
          semesterWeekContext: semesterWeekContext,
          base: calendarDelegate,
          landscapeHeader:
              MediaQuery.orientationOf(context) == Orientation.landscape,
        );

  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    initialEntryMode: initialEntryMode,
    selectableDayPredicate: selectableDayPredicate,
    helpText: helpText,
    cancelText: cancelText,
    confirmText: confirmText,
    locale: locale,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    textDirection: textDirection,
    builder: (pickerContext, child) => _applyAppDialogTheme(
      pickerContext,
      builder?.call(pickerContext, child) ?? child ?? const SizedBox.shrink(),
    ),
    initialDatePickerMode: initialDatePickerMode,
    errorFormatText: errorFormatText,
    errorInvalidText: errorInvalidText,
    fieldHintText: fieldHintText,
    fieldLabelText: fieldLabelText,
    keyboardType: keyboardType,
    anchorPoint: anchorPoint,
    onDatePickerModeChange: onDatePickerModeChange,
    switchToInputEntryModeIcon: switchToInputEntryModeIcon,
    switchToCalendarEntryModeIcon: switchToCalendarEntryModeIcon,
    calendarDelegate: effectiveCalendarDelegate,
  );
}

/// Shows a date-range picker with the shared app theme and native layout.
///
/// Flutter still controls its responsive full-screen and dialog layouts.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  DateTimeRange? initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
  String? helpText,
  String? cancelText,
  String? confirmText,
  String? saveText,
  String? errorFormatText,
  String? errorInvalidText,
  String? errorInvalidRangeText,
  String? fieldStartHintText,
  String? fieldEndHintText,
  String? fieldStartLabelText,
  String? fieldEndLabelText,
  Locale? locale,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  TextDirection? textDirection,
  TransitionBuilder? builder,
  Offset? anchorPoint,
  TextInputType keyboardType = TextInputType.datetime,
  Icon? switchToInputEntryModeIcon,
  Icon? switchToCalendarEntryModeIcon,
  SelectableDayForRangePredicate? selectableDayPredicate,
  CalendarDelegate<DateTime> calendarDelegate =
      const GregorianCalendarDelegate(),
}) {
  return showDateRangePicker(
    context: context,
    initialDateRange: initialDateRange,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    initialEntryMode: initialEntryMode,
    helpText: helpText,
    cancelText: cancelText,
    confirmText: confirmText,
    saveText: saveText,
    errorFormatText: errorFormatText,
    errorInvalidText: errorInvalidText,
    errorInvalidRangeText: errorInvalidRangeText,
    fieldStartHintText: fieldStartHintText,
    fieldEndHintText: fieldEndHintText,
    fieldStartLabelText: fieldStartLabelText,
    fieldEndLabelText: fieldEndLabelText,
    locale: locale,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    textDirection: textDirection,
    builder: (pickerContext, child) => _applyAppDialogTheme(
      pickerContext,
      builder?.call(pickerContext, child) ?? child ?? const SizedBox.shrink(),
    ),
    anchorPoint: anchorPoint,
    keyboardType: keyboardType,
    switchToInputEntryModeIcon: switchToInputEntryModeIcon,
    switchToCalendarEntryModeIcon: switchToCalendarEntryModeIcon,
    selectableDayPredicate: selectableDayPredicate,
    calendarDelegate: calendarDelegate,
  );
}

/// Shows a time picker with the shared app theme and native Material sizing.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TransitionBuilder? builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  TimePickerEntryMode initialEntryMode = TimePickerEntryMode.dial,
  String? cancelText,
  String? confirmText,
  String? helpText,
  String? errorInvalidText,
  String? hourLabelText,
  String? minuteLabelText,
  RouteSettings? routeSettings,
  EntryModeChangeCallback? onEntryModeChanged,
  Offset? anchorPoint,
  Orientation? orientation,
  Icon? switchToInputEntryModeIcon,
  Icon? switchToTimerEntryModeIcon,
  bool emptyInitialInput = false,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (pickerContext, child) => _applyAppDialogTheme(
      pickerContext,
      builder?.call(pickerContext, child) ?? child ?? const SizedBox.shrink(),
    ),
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    initialEntryMode: initialEntryMode,
    cancelText: cancelText,
    confirmText: confirmText,
    helpText: helpText,
    errorInvalidText: errorInvalidText,
    hourLabelText: hourLabelText,
    minuteLabelText: minuteLabelText,
    routeSettings: routeSettings,
    onEntryModeChanged: onEntryModeChanged,
    anchorPoint: anchorPoint,
    orientation: orientation,
    switchToInputEntryModeIcon: switchToInputEntryModeIcon,
    switchToTimerEntryModeIcon: switchToTimerEntryModeIcon,
    emptyInitialInput: emptyInitialInput,
  );
}

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
  bool useGlassSheet = true,
}) {
  final glassConfiguration = LiquidGlassEffectService.configuration;
  final usePackageGlassSheet =
      useGlassSheet &&
      glassConfiguration.enabled &&
      (backgroundColor == null || backgroundColor.a == 0);
  final canPreserveGlassSheetRouteOptions =
      usePackageGlassSheet &&
      barrierLabel == null &&
      elevation == null &&
      shape == null &&
      clipBehavior == null &&
      constraints == null &&
      routeSettings == null &&
      transitionAnimationController == null &&
      anchorPoint == null &&
      sheetAnimationStyle == null &&
      requestFocus == null &&
      navigationBarBackgroundBrightness == null &&
      scrollControlDisabledMaxHeightRatio ==
          _defaultScrollControlDisabledMaxHeightRatio;

  if (canPreserveGlassSheetRouteOptions) {
    return GlassSheet.show<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragIndicator: showDragHandle == true,
      isScrollable: false,
      margin: EdgeInsets.zero,
      topBorderRadius: 28,
      useRootNavigator: useRootNavigator,
      useSafeArea: false,
      barrierColor: barrierColor,
      interactionScale: 1,
      enableInteractionGlow: false,
      enableSaturationGlow: false,
      quality: glassConfiguration.mode == LiquidGlassEffectMode.enhanced
          ? GlassQuality.premium
          : GlassQuality.standard,
      settings: _glassOverlaySettings(context, glassConfiguration),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final bottomInset = media.padding.bottom;
        final transparentSheetProtection =
            backgroundColor != null && backgroundColor.a == 0;
        final sheetBrightness =
            navigationBarBackgroundBrightness ??
            (backgroundColor != null && backgroundColor.a > 0
                ? ThemeData.estimateBrightnessForColor(backgroundColor)
                : Theme.of(sheetContext).brightness);
        // Callers that contain text fields already add viewInsets.bottom to
        // their content. Match showModalBottomSheet's full-height constraint
        // so opening the keyboard does not count that inset twice.
        final availableHeight = media.size.height;
        final maxHeight = isScrollControlled
            ? (availableHeight - (useSafeArea ? media.padding.top : 0))
                  .clamp(0.0, availableHeight)
                  .toDouble()
            : availableHeight * scrollControlDisabledMaxHeightRatio;

        return SizedBox(
          width: double.infinity,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppSystemUiStyle.forBrightness(sheetBrightness),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (transparentSheetProtection && bottomInset > 0)
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
                  top: useSafeArea,
                  left: useSafeArea,
                  right: useSafeArea,
                  bottom: true,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: SizedBox(
                      width: double.infinity,
                      // GlassSheet 不像 showModalBottomSheet 的 _BottomSheet
                      // 那样自带 Material 表面，ListTile/InkWell 会找不到祖先。
                      // 补一层透明 Material 保持与原生弹层一致的行为。
                      child: Material(
                        type: MaterialType.transparency,
                        child: builder(sheetContext),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
      final sheetBrightness =
          navigationBarBackgroundBrightness ??
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

LiquidGlassSettings _glassOverlaySettings(
  BuildContext context,
  LiquidGlassEffectConfiguration configuration,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = colorScheme.brightness == Brightness.dark;
  final enhanced = configuration.mode == LiquidGlassEffectMode.enhanced;
  return LiquidGlassSettings(
    bodyMode: GlassBodyMode.clear,
    glassColor: colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.12),
    thickness: enhanced ? 24 : 18,
    blur: enhanced ? 16 : 12,
    chromaticAberration: enhanced ? 0.008 : 0.004,
    lightIntensity: enhanced ? (isDark ? 0.72 : 0.6) : (isDark ? 0.58 : 0.46),
    ambientStrength: enhanced ? (isDark ? 0.22 : 0.16) : (isDark ? 0.16 : 0.1),
    fresnelStrength: enhanced ? 0.94 : 0.78,
    refractiveIndex: enhanced ? 1.2 : 1.12,
    saturation: enhanced ? 1.06 : 0.95,
    shadowElevation: enhanced ? 1.4 : 0.8,
    backerColor: colorScheme.surface.withValues(
      alpha: liquidGlassBackerOpacity(
        isDark ? (enhanced ? 0.56 : 0.5) : (enhanced ? 0.64 : 0.58),
        configuration,
      ),
    ),
  );
}

enum AppSnackBarType { info, success, warning, error }

class _ActiveGlassToast {
  _ActiveGlassToast(this.dismiss, this.expiryTimer);

  final VoidCallback dismiss;
  final Timer? expiryTimer;
}

class AppSnackBars {
  const AppSnackBars._();

  static final Expando<_ActiveGlassToast> _activeGlassToasts =
      Expando<_ActiveGlassToast>('app-glass-snackbar');

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

    final glassConfiguration = LiquidGlassEffectService.configuration;
    if (glassConfiguration.enabled && Overlay.maybeOf(context) != null) {
      _showGlassToast(
        context,
        messenger,
        message,
        type: type,
        duration: duration,
        action: action,
      );
      return;
    }

    _dismissGlassToast(messenger);

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

  /// Shared entry point for legacy Material SnackBar call sites.
  ///
  /// Simple text notifications use the package toast while preserving the
  /// message, action, persistence, duration, and visibility callback. Custom
  /// layouts and geometry keep their original Material SnackBar behavior.
  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    final content = snackBar.content;
    final canUseGlassToast =
        LiquidGlassEffectService.configuration.enabled &&
        Overlay.maybeOf(context) != null &&
        _isGlassToastCompatible(snackBar);
    if (!canUseGlassToast) {
      _dismissGlassToast(messenger);
      messenger.showSnackBar(snackBar);
      return;
    }

    final text = content as Text;
    final action = snackBar.action;
    _showGlassToast(
      context,
      messenger,
      text.data!,
      duration: snackBar.duration,
      persistent: snackBar.persist,
      action: action == null
          ? null
          : SnackBarAction(label: action.label, onPressed: action.onPressed),
      onVisible: snackBar.onVisible,
    );
  }

  /// Use this when only the messenger survives an async flow or route pop.
  /// There is no reliable overlay context in that case.
  static void showSnackBarFromMessenger(
    ScaffoldMessengerState messenger,
    SnackBar snackBar,
  ) {
    if (!messenger.mounted) return;
    _dismissGlassToast(messenger);
    messenger.showSnackBar(snackBar);
  }

  static bool _isGlassToastCompatible(SnackBar snackBar) {
    final content = snackBar.content;
    final action = snackBar.action;
    return content is Text &&
        content.data != null &&
        content.textSpan == null &&
        content.style == null &&
        content.textAlign == null &&
        content.maxLines == null &&
        content.overflow == null &&
        content.softWrap == null &&
        snackBar.backgroundColor == null &&
        snackBar.elevation == null &&
        snackBar.margin == null &&
        snackBar.padding == null &&
        snackBar.width == null &&
        snackBar.shape == null &&
        snackBar.hitTestBehavior == null &&
        snackBar.behavior != SnackBarBehavior.fixed &&
        snackBar.actionOverflowThreshold == null &&
        snackBar.showCloseIcon != true &&
        snackBar.closeIconColor == null &&
        snackBar.animation == null &&
        snackBar.dismissDirection == null &&
        snackBar.clipBehavior == Clip.hardEdge &&
        (action == null ||
            (action.textColor == null &&
                action.backgroundColor == null &&
                action.disabledTextColor == null &&
                action.disabledBackgroundColor == null));
  }

  static void _showGlassToast(
    BuildContext context,
    ScaffoldMessengerState messenger,
    String message, {
    AppSnackBarType type = AppSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    bool persistent = false,
    SnackBarAction? action,
    VoidCallback? onVisible,
  }) {
    if (!context.mounted) return;
    _dismissGlassToast(messenger);

    final configuration = LiquidGlassEffectService.configuration;
    final toastDuration = persistent ? const Duration(days: 3650) : duration;
    late VoidCallback dismissToast;
    dismissToast = GlassToast.show(
      context,
      message: message,
      type: switch (type) {
        AppSnackBarType.success => GlassToastType.success,
        AppSnackBarType.warning => GlassToastType.warning,
        AppSnackBarType.error => GlassToastType.error,
        AppSnackBarType.info => GlassToastType.info,
      },
      position: GlassToastPosition.bottom,
      duration: toastDuration,
      action: action == null
          ? null
          : GlassToastAction(
              label: action.label,
              onPressed: () {
                action.onPressed();
                dismissToast();
              },
            ),
      settings: _glassOverlaySettings(context, configuration),
      quality: configuration.mode == LiquidGlassEffectMode.enhanced
          ? GlassQuality.premium
          : GlassQuality.standard,
    );

    Timer? expiryTimer;
    if (!persistent) {
      expiryTimer = Timer(
        toastDuration + const Duration(milliseconds: 900),
        () {
          final active = _activeGlassToasts[messenger];
          if (active?.expiryTimer == expiryTimer) {
            _activeGlassToasts[messenger] = null;
          }
        },
      );
    }
    _activeGlassToasts[messenger] = _ActiveGlassToast(
      dismissToast,
      expiryTimer,
    );
    if (onVisible != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onVisible());
    }
  }

  static void _dismissGlassToast(ScaffoldMessengerState messenger) {
    final active = _activeGlassToasts[messenger];
    if (active == null) return;
    active.expiryTimer?.cancel();
    _activeGlassToasts[messenger] = null;
    try {
      active.dismiss();
    } catch (_) {
      // A toast may already have been dismissed by a swipe or its timer.
    }
  }

  static void hideCurrent(ScaffoldMessengerState messenger) {
    _dismissGlassToast(messenger);
    messenger.hideCurrentSnackBar();
  }

  static void removeCurrent(ScaffoldMessengerState messenger) {
    _dismissGlassToast(messenger);
    messenger.removeCurrentSnackBar();
  }

  static void clear(ScaffoldMessengerState messenger) {
    _dismissGlassToast(messenger);
    messenger.clearSnackBars();
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
    final glassConfiguration = LiquidGlassEffectService.configuration;
    if (glassConfiguration.enabled) {
      final colorScheme = Theme.of(context).colorScheme;
      final result = await GlassDialog.show<bool>(
        context: context,
        title: title,
        content: content ?? (message == null ? null : Text(message)),
        barrierDismissible: barrierDismissible,
        barrierColor: colorScheme.scrim.withValues(alpha: 0.42),
        quality: glassConfiguration.mode == LiquidGlassEffectMode.enhanced
            ? GlassQuality.premium
            : GlassQuality.standard,
        settings: _glassOverlaySettings(context, glassConfiguration),
        actions: [
          GlassDialogAction(
            label: cancelLabel,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
          ),
          GlassDialogAction(
            label: confirmLabel,
            isPrimary: !destructive,
            isDestructive: destructive,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
          ),
        ],
      );
      return result ?? false;
    }

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
    showAppDialog<void>(
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
    final glassEnabled = LiquidGlassEffectService.configuration.enabled;
    return showAppModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (sheetContext) => DecoratedBox(
        decoration: BoxDecoration(
          color: glassEnabled ? Colors.transparent : colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: builder(sheetContext),
      ),
    );
  }
}
