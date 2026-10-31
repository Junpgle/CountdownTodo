import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../utils/app_dialogs.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_stamp_animation_queue.dart';
import '../services/habit_sleep_coaching_service.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../utils/app_platform.dart';
import '../../../services/liquid_glass_effect_service.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';
import 'habit_format.dart';
import 'habit_quick_checkin_sheet.dart';
import '../services/habit_streak_service.dart';
import 'habit_celebration_overlay.dart';
import 'habit_checkin_button.dart';
import 'habit_stamp_badge.dart';

/// 单个习惯卡片：进度条 + 类型化操作按钮。
///
/// 操作完成后通过 [onChanged] 通知父级重新加载数据。
class HabitCard extends StatefulWidget {
  final HabitGoal goal;
  final HabitGoalRuleRevision rule;
  final HabitDayProgress dayProgress;

  /// 数据变化后通知父级刷新。
  final VoidCallback onChanged;

  /// 时长型习惯「开始专注」回调（由父级打开番茄钟并预绑定习惯专注信息）。
  final Future<void> Function(HabitGoal goal)? onStartFocus;

  /// 时长型习惯「查看记录」回调（默认由父级跳转详情页）。
  final VoidCallback? onViewRecords;

  /// 点击卡片主体（跳转详情）。
  final VoidCallback? onTap;

  /// 容器变换动画的起点。为空时保持普通卡片渲染。
  final GlobalKey? animationKey;

  /// 首页卡片使用更紧凑的间距；详情页默认保留完整尺寸。
  final bool compact;

  /// 首页壁纸场景使用统一的暗色玻璃与浅色前景。
  final bool isLight;

  final String username;

  /// 睡眠作息渐进训练当前阶段的目标；为空时使用规则最终目标。
  final HabitSleepCoachingMetric? sleepCoachingMetric;

  const HabitCard({
    super.key,
    required this.goal,
    required this.rule,
    required this.dayProgress,
    required this.onChanged,
    this.onStartFocus,
    this.onViewRecords,
    this.onTap,
    this.animationKey,
    this.compact = false,
    this.isLight = false,
    this.username = '',
    this.sleepCoachingMetric,
  });

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> {
  static const double _stampAnimationVisibleFraction = 0.2;

  final Key _visibilityDetectorKey = UniqueKey();
  bool _busy = false;
  bool _isPressed = false;
  bool _justStamped = false;
  double _visibleFraction = 0;
  int? _stampClaimToken;
  Timer? _stampSettleTimer;
  ScrollNotificationObserverState? _scrollObserver;
  Animation<double>? _routeAnimation;

  ColorScheme get _colors => Theme.of(context).colorScheme;

  bool get _canPlayStampAnimation =>
      TickerMode.valuesOf(context).enabled &&
      _visibleFraction >= _stampAnimationVisibleFraction &&
      _isTrulyVisibleOnScreen();

  bool _isTrulyVisibleOnScreen() {
    if (!mounted) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;

    // Route transition must be completely completed before running celebrations.
    final route = ModalRoute.of(context);
    if (route != null &&
        route.animation != null &&
        !route.animation!.isCompleted) {
      return false;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize || !renderBox.attached) {
      return false;
    }

    // 1. Ancestor Viewport check (ListView / SingleChildScrollView / CustomScrollView)
    final viewport = RenderAbstractViewport.maybeOf(renderBox);
    if (viewport != null) {
      try {
        final transform = renderBox.getTransformTo(viewport);
        final boundsInViewport = MatrixUtils.transformRect(
          transform,
          renderBox.paintBounds,
        );
        final visibleInViewport = boundsInViewport.intersect(
          viewport.paintBounds,
        );
        if (visibleInViewport.isEmpty ||
            visibleInViewport.height <
                renderBox.size.height * _stampAnimationVisibleFraction) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }

    // 2. Physical screen window check (cannot be below the fold or above the top)
    try {
      final origin = renderBox.localToGlobal(Offset.zero);
      final cardRect = origin & renderBox.size;
      final screenSize = MediaQuery.sizeOf(context);
      final screenRect = Offset.zero & screenSize;
      final visibleOnScreen = cardRect.intersect(screenRect);
      if (visibleOnScreen.isEmpty ||
          visibleOnScreen.height <
              renderBox.size.height * _stampAnimationVisibleFraction) {
        return false;
      }
    } catch (_) {
      return false;
    }

    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextObserver = ScrollNotificationObserver.maybeOf(context);
    if (_scrollObserver != nextObserver) {
      _scrollObserver?.removeListener(_handleScrollNotification);
      _scrollObserver = nextObserver;
      _scrollObserver?.addListener(_handleScrollNotification);
    }

    final route = ModalRoute.of(context);
    final routeAnimation = route?.animation;
    if (_routeAnimation != routeAnimation) {
      _routeAnimation?.removeStatusListener(_handleRouteStatus);
      _routeAnimation = routeAnimation;
      if (routeAnimation != null && !routeAnimation.isCompleted) {
        routeAnimation.addStatusListener(_handleRouteStatus);
      }
    }

    _scheduleStampAnimationCheck();
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeAnimation?.removeStatusListener(_handleRouteStatus);
      _scheduleStampAnimationCheck();
    }
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification ||
        notification is UserScrollNotification) {
      _scheduleStampAnimationCheck();
    }
  }

  @override
  void didUpdateWidget(HabitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final habitChanged = oldWidget.goal.uuid != widget.goal.uuid;
    final dateChanged = !_sameLogicalDate(
      oldWidget.dayProgress.logicalDate,
      widget.dayProgress.logicalDate,
    );
    if (habitChanged || dateChanged) {
      _releaseStampClaim(
        habitUuid: oldWidget.goal.uuid,
        logicalDate: oldWidget.dayProgress.logicalDate,
      );
      _stampSettleTimer?.cancel();
      _justStamped = false;
      _visibleFraction = 0;
    }

    if (oldWidget.dayProgress.status == HabitDayStatus.met &&
        widget.dayProgress.status != HabitDayStatus.met) {
      HabitStampAnimationQueue.cancel(
        habitUuid: widget.goal.uuid,
        logicalDate: widget.dayProgress.logicalDate,
      );
      _stampSettleTimer?.cancel();
      _releaseStampClaim();
      if (_justStamped) {
        setState(() => _justStamped = false);
      }
    }
    if (!habitChanged &&
        !dateChanged &&
        oldWidget.dayProgress.status != HabitDayStatus.met &&
        widget.dayProgress.status == HabitDayStatus.met &&
        !_justStamped) {
      _triggerStampAnimation();
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    _visibleFraction = info.visibleFraction;
    _scheduleStampAnimationCheck();
  }

  void _scheduleStampAnimationCheck() {
    if (!mounted || _justStamped) return;

    if (!HabitStampAnimationQueue.hasPending(
      habitUuid: widget.goal.uuid,
      logicalDate: widget.dayProgress.logicalDate,
    )) {
      return;
    }

    _stampSettleTimer?.cancel();

    if (!_canPlayStampAnimation) return;

    // Unit test environments zero out the updateInterval for immediate verification.
    final isSynchronousTest =
        VisibilityDetectorController.instance.updateInterval == Duration.zero;
    if (isSynchronousTest) {
      _playQueuedStampAnimationIfReady();
      return;
    }

    // Give a comfortable 320ms visual settle delay after coming stably into view
    // so the user's eye locates the card before the stamp slams down.
    _stampSettleTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || _justStamped) return;
      _playQueuedStampAnimationIfReady();
    });
  }

  void _playQueuedStampAnimationIfReady() {
    if (!mounted || !_canPlayStampAnimation || _justStamped) return;
    final token = HabitStampAnimationQueue.claim(
      habitUuid: widget.goal.uuid,
      logicalDate: widget.dayProgress.logicalDate,
    );
    if (token == null) return;
    _stampClaimToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stampClaimToken != token) return;
      if (!_canPlayStampAnimation) {
        HabitStampAnimationQueue.release(
          habitUuid: widget.goal.uuid,
          logicalDate: widget.dayProgress.logicalDate,
          token: token,
        );
        _stampClaimToken = null;
        return;
      }
      final completed = HabitStampAnimationQueue.complete(
        habitUuid: widget.goal.uuid,
        logicalDate: widget.dayProgress.logicalDate,
        token: token,
      );
      _stampClaimToken = null;
      if (completed) _startStampAnimation();
    });
  }

  void _triggerStampAnimation() {
    if (!mounted) return;
    HabitStampAnimationQueue.request(
      habitUuid: widget.goal.uuid,
      logicalDate: widget.dayProgress.logicalDate,
    );
    _scheduleStampAnimationCheck();
  }

  void _startStampAnimation() {
    if (_justStamped) return;
    setState(() => _justStamped = true);
  }

  void _releaseStampClaim({String? habitUuid, DateTime? logicalDate}) {
    final token = _stampClaimToken;
    if (token == null) return;
    HabitStampAnimationQueue.release(
      habitUuid: habitUuid ?? widget.goal.uuid,
      logicalDate: logicalDate ?? widget.dayProgress.logicalDate,
      token: token,
    );
    _stampClaimToken = null;
  }

  bool _sameLogicalDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  @override
  void dispose() {
    _stampSettleTimer?.cancel();
    _scrollObserver?.removeListener(_handleScrollNotification);
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    _releaseStampClaim();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.dayProgress.progress;
    final status = widget.dayProgress.status;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _statusColor(status);

    return VisibilityDetector(
      key: _visibilityDetectorKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.onTap != null) setState(() => _isPressed = true);
        },
        onTapUp: (_) {
          if (widget.onTap != null) {
            setState(() => _isPressed = false);
          }
        },
        onTap: widget.onTap,
        onTapCancel: () {
          if (widget.onTap != null) setState(() => _isPressed = false);
        },
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: OptionalLiquidGlassCard(
            key: widget.animationKey,
            margin: EdgeInsets.symmetric(vertical: widget.compact ? 2 : 6),
            borderRadius: widget.compact ? 18 : 24,
            tint: statusColor.withValues(alpha: 0.16),
            isDark: isDark,
            fallbackDecoration: BoxDecoration(
              color: _colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(widget.compact ? 18 : 24),
              border: Border.all(
                color: _colors.onSurface.withValues(alpha: isDark ? 0.1 : 0.05),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _colors.shadow.withValues(alpha: 0.04),
                  blurRadius: AppPlatform.isAndroid
                      ? (widget.compact ? 8 : 12)
                      : (widget.compact ? 16 : 24),
                  offset: AppPlatform.isAndroid
                      ? const Offset(0, 4)
                      : (widget.compact
                            ? const Offset(0, 4)
                            : const Offset(0, 8)),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.compact ? 18 : 24),
              child: Stack(
                children: [
                  // 1. 底层水印印章：右下角出血位，超出边界被 ClipRRect 裁切，形成半透明防伪印质感
                  if (_justStamped || status == HabitDayStatus.met)
                    Positioned(
                      right: widget.compact ? -18 : -22,
                      bottom: widget.compact ? -16 : -20,
                      child: IgnorePointer(
                        child: HabitStampBadge(
                          animate: _justStamped,
                          text: '已达成',
                          size: widget.compact ? 116 : 136,
                          opacity: 0.22,
                          color: _colors.cdtSuccess,
                          onAnimationComplete: () {
                            if (mounted && _justStamped) {
                              setState(() => _justStamped = false);
                            }
                          },
                        ),
                      ),
                    ),

                  // 2. 前景主体：文字、进度、操作按钮（在水印上层渲染，信息绝不被遮挡）
                  Padding(
                    padding: widget.compact
                        ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
                        : const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(progress, status),
                        if (widget.goal.sourceType !=
                                HabitSourceType.timeCheckIn &&
                            widget.goal.sourceType !=
                                HabitSourceType.recurringTodo) ...[
                          SizedBox(height: widget.compact ? 8 : 14),
                          _buildProgressBar(progress, status),
                        ],
                        SizedBox(height: widget.compact ? 8 : 12),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            // 吸收操作按钮区域的点击手势，阻止向上冒泡触发卡片全局详情跳转
                          },
                          onTapDown: (_) {},
                          onTapUp: (_) {},
                          onTapCancel: () {},
                          child: _buildActions(progress, status),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 头部：图标 + 名称 + 状态 ────────────────────────
  Widget _buildHeader(HabitProgress progress, HabitDayStatus status) {
    final useWallpaperGlass =
        widget.isLight && LiquidGlassEffectService.configuration.enabled;
    final textColor = useWallpaperGlass ? _colors.onPrimary : _colors.onSurface;
    final subColor = useWallpaperGlass
        ? _colors.onPrimary.withValues(alpha: 0.7)
        : _colors.onSurfaceVariant;
    final statusColor = _statusColor(status);

    return Row(
      children: [
        Container(
          width: widget.compact ? 32 : 40,
          height: widget.compact ? 32 : 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            widget.goal.icon.isNotEmpty ? widget.goal.icon : '🎯',
            style: TextStyle(fontSize: widget.compact ? 18 : 22),
          ),
        ),
        SizedBox(width: widget.compact ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.goal.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.compact ? 14 : 16,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _subtitle(status, progress),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.compact ? 11 : 12,
                  color: subColor,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: widget.compact ? 6 : 8),
        _buildStatusBadge(status),
      ],
    );
  }

  String _subtitle(HabitDayStatus status, HabitProgress progress) {
    final String base;
    switch (widget.goal.sourceType) {
      case HabitSourceType.recurringTodo:
        base = HabitText.periodLabel(widget.rule);
      case HabitSourceType.pomodoroTag:
        base =
            '${HabitText.periodLabel(widget.rule)} · '
            '${HabitText.durationProgress(progress)}';
      case HabitSourceType.durationCheckIn:
        final coachingTarget = _sleepCoachingTargetLabel;
        base =
            '${HabitText.periodLabel(widget.rule)} · '
            '${coachingTarget == null ? HabitText.durationProgressForGoal(widget.goal, progress) : '${HabitText.formatDuration(progress.currentValue.round())} · '
                      '本期目标 $coachingTarget'}';
      case HabitSourceType.quantityCheckIn:
        final unit = widget.rule.unit;
        base =
            '${HabitText.periodLabel(widget.rule)} · '
            '${HabitText.amountProgress(progress, unit)}';
      case HabitSourceType.timeCheckIn:
        final coachingTarget = _sleepCoachingTargetLabel;
        base =
            '${HabitText.periodLabel(widget.rule)} · '
            '目标 ${coachingTarget ?? HabitText.targetTime(widget.rule.targetTimeMinute)}';
    }
    if (widget.rule.hasPlanningBlock(widget.goal)) {
      final startText = HabitText.targetTime(
        widget.rule.effectivePreferredStartMinute(),
      );
      final minutes = widget.rule.effectivePlannedMinutes(widget.goal);
      return '$base · 预留 $startText (${minutes}m)';
    }
    return base;
  }

  bool get _canQuickFocus =>
      widget.onStartFocus != null &&
      (widget.rule.hasPlanningBlock(widget.goal) ||
          widget.rule.reminderPolicy.focusTagUuids.isNotEmpty ||
          widget.goal.defaultFocusMinutes != null);

  Widget _buildQuickFocusButton() {
    return IconButton.filledTonal(
      tooltip: '开始专注（达标自动打卡）',
      onPressed: _busy ? null : _startFocus,
      icon: Icon(Icons.timer_outlined, size: widget.compact ? 16 : 18),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
        ),
      ),
    );
  }

  String? get _sleepCoachingTargetLabel {
    final metric = widget.sleepCoachingMetric;
    if (metric == null || !metric.isAvailable) return null;
    switch (metric.kind) {
      case HabitAdaptationKind.earlySleep:
      case HabitAdaptationKind.earlyWake:
        return HabitText.targetTime(metric.stageTarget);
      case HabitAdaptationKind.sleepDuration:
        return HabitText.formatDuration(metric.stageTarget * 60);
      default:
        return null;
    }
  }

  Color _statusColor(HabitDayStatus status) {
    switch (status) {
      case HabitDayStatus.met:
        return _colors.cdtSuccess;
      case HabitDayStatus.missed:
        return _colors.error;
      case HabitDayStatus.inProgress:
        return _colors.primary;
      case HabitDayStatus.frozen:
        return _colors.secondary;
      default:
        return _colors.outlineVariant;
    }
  }

  Widget _buildStatusBadge(HabitDayStatus status) {
    final color = _statusColor(status);
    final String text;
    switch (status) {
      case HabitDayStatus.met:
        text = '已完成';
        break;
      case HabitDayStatus.missed:
        text = '未完成';
        break;
      case HabitDayStatus.inProgress:
        text = '进行中';
        break;
      case HabitDayStatus.notPlanned:
        text = '今日无计划';
        break;
      case HabitDayStatus.skipped:
        text = '已跳过';
        break;
      case HabitDayStatus.frozen:
        text = '免扣保护';
        break;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          child: child,
        );
      },
      child: Container(
        key: ValueKey(status),
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 6 : 8,
          vertical: widget.compact ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: status == HabitDayStatus.met ? 0.16 : 0.1,
          ),
          borderRadius: BorderRadius.circular(6),
          border: status == HabitDayStatus.met
              ? Border.all(color: color.withValues(alpha: 0.35), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == HabitDayStatus.met) ...[
              Icon(
                Icons.check_circle_rounded,
                size: widget.compact ? 11 : 12,
                color: color,
              ),
              const SizedBox(width: 3),
            ] else if (status == HabitDayStatus.frozen) ...[
              Icon(
                Icons.shield_outlined,
                size: widget.compact ? 11 : 12,
                color: color,
              ),
              const SizedBox(width: 3),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: widget.compact ? 10 : 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 进度条 ──────────────────────────────────────────
  Widget _buildProgressBar(HabitProgress progress, HabitDayStatus status) {
    final barColor = _statusColor(status);
    final coaching = widget.sleepCoachingMetric;
    final ratio =
        coaching?.kind == HabitAdaptationKind.sleepDuration &&
            coaching!.stageTarget > 0
        ? (progress.currentValue / (coaching.stageTarget * 60)).clamp(0.0, 1.0)
        : progress.completionRatio.clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: ratio),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      builder: (context, animatedRatio, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: animatedRatio,
            minHeight: widget.compact ? 4 : 5,
            backgroundColor:
                widget.isLight && LiquidGlassEffectService.configuration.enabled
                ? _colors.onPrimary.withValues(alpha: 0.18)
                : _colors.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        );
      },
    );
  }

  // ── 操作区 ──────────────────────────────────────────
  Widget _buildActions(HabitProgress progress, HabitDayStatus status) {
    switch (widget.goal.sourceType) {
      case HabitSourceType.recurringTodo:
        return _buildCompletionAction(progress);
      case HabitSourceType.pomodoroTag:
        return _buildDurationAction(progress);
      case HabitSourceType.durationCheckIn:
        return _buildSleepDurationAction();
      case HabitSourceType.quantityCheckIn:
        return _buildQuantityAction(status);
      case HabitSourceType.timeCheckIn:
        return _buildTimeAction(progress);
    }
  }

  Widget _buildCompletionAction(HabitProgress progress) {
    final done = progress.goalMet;
    return Row(
      children: [
        Expanded(
          child: done
              ? FilledButton.tonal(
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: widget.compact ? 8 : 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        widget.compact ? 10 : 12,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: widget.compact ? 16 : 18,
                      ),
                      SizedBox(width: widget.compact ? 4 : 6),
                      const Text('已完成'),
                    ],
                  ),
                )
              : HabitCelebrationTrigger(
                  enabled: !_busy,
                  burstColor: _colors.cdtSuccess,
                  borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
                  holdHint: '长按以完成习惯',
                  semanticLabel: '完成习惯：${widget.goal.name}',
                  onCheckIn: () => _toggleDone(progress),
                  child: IgnorePointer(
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: widget.compact ? 8 : 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              widget.compact ? 10 : 12,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              size: widget.compact ? 16 : 18,
                            ),
                            SizedBox(width: widget.compact ? 4 : 6),
                            const Text('完成'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        if (!done && _canQuickFocus) ...[
          const SizedBox(width: 8),
          _buildQuickFocusButton(),
        ],
        if (done) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy ? null : () => _toggleDone(progress),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 16,
                vertical: widget.compact ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
            child: const Text('撤销'),
          ),
        ],
      ],
    );
  }

  Future<void> _toggleDone(HabitProgress progress) async {
    final wasGoalMet = progress.goalMet;
    if (wasGoalMet) {
      setState(() => _justStamped = false);
    }
    setState(() => _busy = true);
    try {
      await HabitRepository.setCompletion(
        goal: widget.goal,
        logicalDate: DateTime.now(),
        done: !wasGoalMet,
        username: widget.username,
      );
      if (!wasGoalMet && mounted) {
        _triggerStampAnimation();
        _checkAndTriggerCelebration();
      } else if (mounted) {
        setState(() => _justStamped = false);
      }
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildDurationAction(HabitProgress progress) {
    final currentSeconds = progress.currentValue;
    final isMet = progress.goalMet;

    if (isMet) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.tonal(
              onPressed: null,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: widget.compact ? 8 : 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: widget.compact ? 16 : 18,
                  ),
                  SizedBox(width: widget.compact ? 4 : 6),
                  Text(
                    widget.compact
                        ? '已达标'
                        : '已达标 (${(currentSeconds / 60).round()}分钟)',
                  ),
                ],
              ),
            ),
          ),
          if (widget.onStartFocus != null) ...[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '继续专注',
              onPressed: _busy ? null : _startFocus,
              icon: Icon(
                Icons.play_arrow_rounded,
                size: widget.compact ? 16 : 18,
              ),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
                ),
              ),
            ),
          ],
          if (widget.onViewRecords != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: widget.onViewRecords,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 10 : 16,
                  vertical: widget.compact ? 8 : 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
                ),
              ),
              child: const Text('记录'),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.tonal(
            onPressed: _busy || widget.onStartFocus == null
                ? null
                : _startFocus,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: widget.compact ? 8 : 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: widget.compact ? 16 : 18),
                SizedBox(width: widget.compact ? 4 : 6),
                const Text('开始专注'),
              ],
            ),
          ),
        ),
        if (widget.onViewRecords != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.onViewRecords,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 16,
                vertical: widget.compact ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
            child: const Text('记录'),
          ),
        ],
      ],
    );
  }

  Future<void> _startFocus() async {
    final onStartFocus = widget.onStartFocus;
    if (_busy || onStartFocus == null) return;
    setState(() => _busy = true);
    try {
      await onStartFocus(widget.goal);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildSleepDurationAction() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonal(
            onPressed: _busy
                ? null
                : () async {
                    await HabitQuickCheckInSheet.show(
                      context: context,
                      goal: widget.goal,
                      rule: widget.rule,
                      username: widget.username,
                      logicalDate: widget.dayProgress.logicalDate,
                      onChanged: widget.onChanged,
                    );
                  },
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: widget.compact ? 8 : 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.edit_calendar_rounded,
                  size: widget.compact ? 16 : 18,
                ),
                SizedBox(width: widget.compact ? 4 : 6),
                Text('手动修正睡眠时长'),
              ],
            ),
          ),
        ),
        if (widget.onViewRecords != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.onViewRecords,
            style: TextButton.styleFrom(
              minimumSize: Size(0, widget.compact ? 36 : 40),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 8 : 12,
              ),
            ),
            child: const Text('历史'),
          ),
        ],
      ],
    );
  }

  Widget _buildQuantityAction(HabitDayStatus status) {
    final adaptation = HabitAdaptationService.forHabit(widget.goal);
    final quickValues = widget.rule.quickValues.isNotEmpty
        ? widget.rule.quickValues
        : adaptation?.suggestedQuickValues ?? const [1];
    final unit = widget.rule.unit;

    return Wrap(
      spacing: widget.compact ? 6 : 8,
      runSpacing: widget.compact ? 4 : 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...quickValues
            .take(3)
            .map(
              (v) => _quickValueChip(
                v.toDouble(),
                unit,
                label: adaptation?.quickLabel(v, unit: unit),
              ),
            ),
        TextButton(
          onPressed: _busy ? null : () => _openQuantityCustomDialog(),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 12,
              vertical: widget.compact ? 6 : 8,
            ),
            minimumSize: Size(0, widget.compact ? 32 : 36),
          ),
          child: const Text('自定义'),
        ),
        if (status != HabitDayStatus.met && _canQuickFocus)
          _buildQuickFocusButton(),
      ],
    );
  }

  Widget _quickValueChip(double value, String unit, {String? label}) {
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
    final chipLabel = label ?? (unit.isNotEmpty ? '$text $unit' : text);
    return HabitCelebrationTrigger(
      burstColor: _colors.primary,
      holdHint: '长按打卡 $chipLabel',
      semanticLabel: '${widget.goal.name}，增加 $chipLabel',
      enabled: !_busy,
      onCheckIn: () => _quickCheckIn(value, text),
      child: IgnorePointer(
        child: FilledButton.tonal(
          onPressed: () {},
          style: FilledButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 12 : 16,
              vertical: widget.compact ? 6 : 8,
            ),
            minimumSize: Size(0, widget.compact ? 32 : 36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
            ),
          ),
          child: Text(chipLabel),
        ),
      ),
    );
  }

  Future<void> _quickCheckIn(double value, String label) async {
    final wasGoalMet = widget.dayProgress.progress.goalMet;
    setState(() => _busy = true);
    try {
      final checkIn = await HabitRepository.addCheckIn(
        goal: widget.goal,
        rule: widget.rule,
        localOccurredAt: DateTime.now(),
        value: value,
      );
      final target = widget.rule.targetValue;
      final current = widget.dayProgress.progress.currentValue;
      final isNowGoalMet = (current + value >= target);
      if (isNowGoalMet && mounted) {
        _triggerStampAnimation();
        if (!wasGoalMet) {
          _checkAndTriggerCelebration();
        }
      }
      widget.onChanged();
      _showUndoSnackBar('已记录 $label${widget.rule.unit}', checkIn);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openQuantityCustomDialog() async {
    await HabitQuickCheckInSheet.show(
      context: context,
      goal: widget.goal,
      rule: widget.rule,
      username: widget.username,
      onChanged: widget.onChanged,
    );
  }

  Widget _buildTimeAction(HabitProgress progress) {
    final actual = progress.firstRecordAt;

    return Row(
      children: [
        if (actual != null) ...[
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 8 : 10,
              vertical: widget.compact ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: _colors.cdtSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${HabitText.timeOfDay(actual)} · '
              '${HabitText.timePointStatus(widget.rule, progress)}',
              style: TextStyle(
                fontSize: widget.compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: _colors.cdtSuccess,
              ),
            ),
          ),
          SizedBox(width: widget.compact ? 6 : 8),
        ],
        Expanded(
          child: HabitCelebrationTrigger(
            enabled: !_busy,
            burstColor: _colors.cdtSuccess,
            borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
            holdHint: actual == null ? '长按完成打卡' : '长按重新打卡',
            semanticLabel: actual == null
                ? '${widget.goal.name}，记录当前时间'
                : '${widget.goal.name}，修改打卡时间',
            onCheckIn: actual == null
                ? () => _recordTimeCheckInDirectly()
                : () => _openTimePicker(actual),
            child: IgnorePointer(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: widget.compact ? 8 : 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        widget.compact ? 10 : 12,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        actual == null
                            ? Icons.check_rounded
                            : Icons.edit_calendar_rounded,
                        size: widget.compact ? 16 : 18,
                      ),
                      SizedBox(width: widget.compact ? 4 : 6),
                      Text(actual == null ? '打卡' : '重新打卡'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (actual == null) ...[
          if (_canQuickFocus) ...[
            const SizedBox(width: 8),
            _buildQuickFocusButton(),
          ],
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: '指定时间打卡',
            onPressed: _busy ? null : () => _openTimePicker(null),
            icon: Icon(Icons.schedule_rounded, size: widget.compact ? 16 : 18),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _recordTimeCheckInDirectly() async {
    final now = DateTime.now();
    final wasGoalMet = widget.dayProgress.progress.goalMet;
    setState(() => _busy = true);
    try {
      final checkIn = await HabitRepository.addCheckIn(
        goal: widget.goal,
        rule: widget.rule,
        localOccurredAt: now,
        source: HabitCheckInSource.manual,
      );
      if (mounted) {
        _triggerStampAnimation();
        if (!wasGoalMet) {
          _checkAndTriggerCelebration();
        }
      }
      widget.onChanged();
      _showTimeCheckInSnackBar(now, checkIn);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showTimeCheckInSnackBar(DateTime occurred, HabitCheckIn checkIn) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    AppSnackBars.hideCurrent(messenger);
    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: Text('已打卡 ${HabitText.timeOfDay(occurred)}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '修改时间',
          onPressed: () => _openTimePicker(occurred),
        ),
      ),
    );
  }

  Future<void> _openTimePicker(DateTime? existing) async {
    final now = DateTime.now();
    final wasGoalMet = widget.dayProgress.progress.goalMet;
    final picked = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(existing ?? now),
      helpText: '记录「${widget.goal.name}」的时间',
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final occurred = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      final checkIn = await HabitRepository.addCheckIn(
        goal: widget.goal,
        rule: widget.rule,
        localOccurredAt: occurred,
        source: HabitCheckInSource.manual,
      );
      if (mounted) {
        _triggerStampAnimation();
        if (!wasGoalMet) {
          _checkAndTriggerCelebration();
        }
      }
      widget.onChanged();
      _showUndoSnackBar('已记录 ${HabitText.timeOfDay(occurred)}', checkIn);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkAndTriggerCelebration() async {
    _triggerStampAnimation();
    HabitStreakSummary? streakSummary;
    try {
      streakSummary = await HabitStreakService.summarize(
        habit: widget.goal,
        rules: [widget.rule],
      );
    } catch (_) {}
    // 延迟 420ms 先让卡片上的印章猛烈盖下，随后升起全屏庆祝
    await Future.delayed(const Duration(milliseconds: 420));
    if (mounted) {
      await showHabitGoalMetCelebration(
        context,
        goal: widget.goal,
        streakDays: streakSummary?.currentStreak ?? 0,
      );
    }
  }

  void _showUndoSnackBar(String message, HabitCheckIn checkIn) {
    final wasReplacement = checkIn.replacedPrevious;
    final messenger = ScaffoldMessenger.of(context);
    AppSnackBars.hideCurrent(messenger);
    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: Text(wasReplacement ? '$message（已覆盖上一条记录）' : message),
        duration: const Duration(seconds: 4),
        action: wasReplacement
            ? null
            : SnackBarAction(
                label: '撤销',
                onPressed: () async {
                  await HabitRepository.deleteCheckIn(checkIn);
                  widget.onChanged();
                },
              ),
      ),
    );
  }
}
