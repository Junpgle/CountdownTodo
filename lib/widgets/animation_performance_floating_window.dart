import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/animation_settings_page.dart';
import '../services/animation_performance_monitor_service.dart';
import '../services/liquid_glass_effect_service.dart';
import '../services/power_save_mode_service.dart';
import '../utils/navigator_utils.dart';

/// 全局流畅度与负载压力悬浮窗（支持拖拽定位、胶囊收起与展开详情）
class AnimationPerformanceFloatingWindow extends StatefulWidget {
  const AnimationPerformanceFloatingWindow({super.key});

  @override
  State<AnimationPerformanceFloatingWindow> createState() =>
      _AnimationPerformanceFloatingWindowState();
}

class _AnimationPerformanceFloatingWindowState
    extends State<AnimationPerformanceFloatingWindow> {
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable:
          AnimationPerformanceMonitorService.isFloatingActiveListenable,
      builder: (context, isActive, _) {
        if (!isActive) return const SizedBox.shrink();

        return ValueListenableBuilder<bool>(
          valueListenable:
              AnimationPerformanceMonitorService.isExpandedListenable,
          builder: (context, isExpanded, _) {
            return ValueListenableBuilder<PerformanceMetricsSnapshot>(
              valueListenable:
                  AnimationPerformanceMonitorService.metricsListenable,
              builder: (context, snapshot, _) {
                return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
                  valueListenable:
                      LiquidGlassEffectService.configurationListenable,
                  builder: (context, _, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: PowerSaveModeService.enabledListenable,
                      builder: (context, _, _) {
                        final pressure =
                            AnimationPerformanceMonitorService.evaluateCurrentPressure();
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final screenSize = MediaQuery.sizeOf(context);
                            final topPadding = MediaQuery.paddingOf(context)
                                .top;
                            final windowWidth = isExpanded ? 320.0 : 288.0;
                            final windowHeight = isExpanded ? 390.0 : 38.0;

                            // 初始化默认位置：右上角
                            _position ??= Offset(
                              (screenSize.width - windowWidth - 16).clamp(
                                8.0,
                                screenSize.width - windowWidth - 8.0,
                              ),
                              math.max(topPadding + 16, 76.0),
                            );

                            // 约束位置在屏幕视口内，防止被拖出屏幕外
                            final double clampedX = _position!.dx
                                .clamp(
                                  8.0,
                                  math.max<double>(
                                    8.0,
                                    screenSize.width - windowWidth - 8.0,
                                  ),
                                )
                                .toDouble();
                            final double clampedY = _position!.dy
                                .clamp(
                                  topPadding + 8.0,
                                  math.max<double>(
                                    8.0,
                                    screenSize.height - windowHeight - 8.0,
                                  ),
                                )
                                .toDouble();
                            final currentPos = Offset(clampedX, clampedY);

                            return Stack(
                              children: [
                                Positioned(
                                  left: currentPos.dx,
                                  top: currentPos.dy,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanUpdate: (details) {
                                      setState(() {
                                        _position = Offset(
                                          currentPos.dx + details.delta.dx,
                                          currentPos.dy + details.delta.dy,
                                        );
                                      });
                                    },
                                    child: AnimatedSize(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      child: isExpanded
                                          ? _buildExpandedCard(
                                              context: context,
                                              snapshot: snapshot,
                                              pressure: pressure,
                                              width: windowWidth,
                                            )
                                          : _buildCompactCapsule(
                                              context: context,
                                              snapshot: snapshot,
                                              pressure: pressure,
                                              width: windowWidth,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// 简洁胶囊悬浮窗模式
  Widget _buildCompactCapsule({
    required BuildContext context,
    required PerformanceMetricsSnapshot snapshot,
    required LoadPressureEvaluation pressure,
    required double width,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final fpsOk = snapshot.currentFps >= (snapshot.targetRefreshRate * 0.9);
    final statusColor = fpsOk ? colorScheme.primary : colorScheme.error;

    return Material(
      color: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        key: const ValueKey('animation-performance-floating-capsule'),
        width: width,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF1E222B) : Colors.white).withValues(
            alpha: isDark ? 0.94 : 0.96,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: pressure.isHighPressure
                ? colorScheme.error.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.drag_indicator_rounded,
              size: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${snapshot.currentFps.toStringAsFixed(1)} FPS',
                      key: const ValueKey(
                        'animation-performance-floating-fps-capsule',
                      ),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '·',
                        style: TextStyle(
                          color: colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${snapshot.totalRenderMs.toStringAsFixed(1)}ms',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: pressure.getLevelContainerColor(colorScheme),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                pressure.levelLabel,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: pressure.getLevelColor(colorScheme),
                ),
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              key: const ValueKey('animation-performance-floating-expand-btn'),
              behavior: HitTestBehavior.opaque,
              onTap: () => AnimationPerformanceMonitorService.setExpanded(true),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.open_in_full_rounded,
                  size: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            GestureDetector(
              key: const ValueKey('animation-performance-floating-close-btn'),
              behavior: HitTestBehavior.opaque,
              onTap: () => AnimationPerformanceMonitorService.hideFloating(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 展开详情面板模式
  Widget _buildExpandedCard({
    required BuildContext context,
    required PerformanceMetricsSnapshot snapshot,
    required LoadPressureEvaluation pressure,
    required double width,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      elevation: 10,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        key: const ValueKey('animation-performance-floating-expanded-card'),
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF1E222B) : Colors.white).withValues(
            alpha: isDark ? 0.96 : 0.98,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: pressure.isHighPressure
                ? colorScheme.error.withValues(alpha: 0.45)
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.16),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶栏拖拽条与操作按钮
            Row(
              children: [
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.insights_rounded,
                  size: 17,
                  color: pressure.getLevelColor(colorScheme),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '实时性能监控',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${snapshot.targetRefreshRate.round()} Hz',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  key: const ValueKey(
                    'animation-performance-floating-collapse-btn',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      AnimationPerformanceMonitorService.setExpanded(false),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_fullscreen_rounded,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                GestureDetector(
                  key: const ValueKey(
                    'animation-performance-floating-expanded-close-btn',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      AnimationPerformanceMonitorService.hideFloating(),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 三项核心流畅度指标平铺
            Row(
              children: [
                Expanded(
                  child: _buildMiniStat(
                    label: '实时帧率',
                    value: '${snapshot.currentFps.toStringAsFixed(1)} FPS',
                    color:
                        snapshot.currentFps >=
                            (snapshot.targetRefreshRate * 0.9)
                        ? colorScheme.primary
                        : colorScheme.error,
                    subtext: '稳定性 ${snapshot.smoothnessPercent.round()}%',
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMiniStat(
                    label: '渲染耗时',
                    value: '${snapshot.totalRenderMs.toStringAsFixed(1)} ms',
                    color: snapshot.totalRenderMs <= snapshot.frameBudgetMs
                        ? colorScheme.primary
                        : colorScheme.error,
                    subtext:
                        '${snapshot.avgBuildMs.toStringAsFixed(1)} + ${snapshot.avgRasterMs.toStringAsFixed(1)}ms',
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMiniStat(
                    label: '掉帧计数',
                    value: '${snapshot.jankCount} 帧',
                    color: snapshot.jankCount == 0
                        ? colorScheme.primary
                        : colorScheme.tertiary,
                    subtext: snapshot.jankCount == 0 ? '近帧满帧' : '超预算丢帧',
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 综合负载压力进度条
            Row(
              children: [
                Text(
                  '综合负载压力',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: pressure.getLevelContainerColor(colorScheme),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${pressure.levelLabel} (${pressure.scorePercent}%)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: pressure.getLevelColor(colorScheme),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pressure.scorePercent / 100.0,
                minHeight: 5,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: pressure.getLevelColor(colorScheme),
              ),
            ),
            const SizedBox(height: 8),

            // 特效负载拆解标签
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: pressure.factors.take(3).map((factor) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    factor,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 10),

            // 警示卡片注明：开启较多特效可能会导致卡顿
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: pressure.isHighPressure
                    ? colorScheme.errorContainer.withValues(alpha: 0.2)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: pressure.isHighPressure
                      ? colorScheme.error.withValues(alpha: 0.3)
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    pressure.isHighPressure
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: pressure.isHighPressure
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '开启较多特效可能会导致卡顿；中低端机型如出现滑动不流畅建议切换为平衡预设。',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.35,
                        color: pressure.isHighPressure
                            ? colorScheme.onErrorContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // 前往动画设置快捷入口
            SizedBox(
              width: double.infinity,
              height: 32,
              child: FilledButton.tonalIcon(
                key: const ValueKey(
                  'animation-performance-floating-go-settings-btn',
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.tune_rounded, size: 14),
                label: const Text('前往动画设置调参', style: TextStyle(fontSize: 11.5)),
                onPressed: () {
                  final navContext = appNavigatorKey.currentContext;
                  if (navContext != null) {
                    Navigator.of(navContext).push(
                      MaterialPageRoute(
                        builder: (_) => const AnimationSettingsPage(),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
    required String subtext,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtext,
            style: TextStyle(
              fontSize: 8.5,
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
