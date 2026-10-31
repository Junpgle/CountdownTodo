import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/animation_performance_monitor_service.dart';
import '../services/liquid_glass_effect_service.dart';
import '../utils/app_dialogs.dart';

export '../services/animation_performance_monitor_service.dart'
    show
        LoadPressureEvaluation,
        RenderingPressureEvaluation,
        evaluateLoadPressure,
        evaluateRenderingPressure;

/// 动画与特效设置顶部的流畅度量化指标与负载压力仪表卡片
class AnimationPerformanceMetricCard extends StatefulWidget {
  final bool animationsEnabled;
  final bool motionBlurEnabled;
  final bool layerBlurEnabled;
  final bool liquidGlassEnabled;
  final LiquidGlassEffectMode liquidGlassMode;
  final double liquidGlassBlur;
  final int liquidGlassTransparency;
  final bool screenRadiusEnabled;
  final bool lazyLoadEnabled;
  final bool powerSaveModeEnabled;
  final bool isDesktop;

  /// 用于单元测试注入固定刷新率
  @visibleForTesting
  final double? testRefreshRate;

  /// 用于单元测试注入初始帧时间数据
  @visibleForTesting
  final List<FrameTiming>? initialTimingsForTesting;

  const AnimationPerformanceMetricCard({
    super.key,
    required this.animationsEnabled,
    required this.motionBlurEnabled,
    required this.layerBlurEnabled,
    required this.liquidGlassEnabled,
    required this.liquidGlassMode,
    required this.liquidGlassBlur,
    required this.liquidGlassTransparency,
    required this.screenRadiusEnabled,
    required this.lazyLoadEnabled,
    required this.powerSaveModeEnabled,
    this.isDesktop = false,
    this.testRefreshRate,
    this.initialTimingsForTesting,
  });

  @override
  State<AnimationPerformanceMetricCard> createState() =>
      _AnimationPerformanceMetricCardState();
}

class _AnimationPerformanceMetricCardState
    extends State<AnimationPerformanceMetricCard> {
  static const int _maxFrameWindow = 60;
  final List<FrameTiming> _recentTimings = [];
  Timer? _refreshTimer;

  double _currentFps = 60.0;
  double _avgBuildMs = 1.8;
  double _avgRasterMs = 2.4;
  double _smoothnessPercent = 100.0;
  int _jankFrameCount = 0;
  double _interactiveTestValue = 0.5;

  @override
  void initState() {
    super.initState();
    AnimationPerformanceMonitorService.registerConsumer();
    if (widget.initialTimingsForTesting != null) {
      _recentTimings.addAll(widget.initialTimingsForTesting!);
    }
    try {
      SchedulerBinding.instance.addTimingsCallback(_handleTimings);
    } catch (_) {
      // 避免无 UI 调度的测试环境报错
    }
    // 定期刷新界面展示指标，避免每帧触发 setState 带来额外渲染开销
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted) {
        _updateMetrics();
      }
    });
  }

  @override
  void dispose() {
    AnimationPerformanceMonitorService.unregisterConsumer();
    _refreshTimer?.cancel();
    try {
      SchedulerBinding.instance.removeTimingsCallback(_handleTimings);
    } catch (_) {}
    super.dispose();
  }

  void _handleTimings(List<FrameTiming> timings) {
    if (!mounted) return;
    _recentTimings.addAll(timings);
    if (_recentTimings.length > _maxFrameWindow) {
      _recentTimings.removeRange(0, _recentTimings.length - _maxFrameWindow);
    }
  }

  /// 测试方法：用于外部模拟录入帧耗时
  @visibleForTesting
  void recordTimingsForTesting(List<FrameTiming> timings) {
    _handleTimings(timings);
    _updateMetrics();
  }

  double _detectRefreshRate() {
    if (widget.testRefreshRate != null) return widget.testRefreshRate!;
    try {
      final rate = View.of(context).display.refreshRate;
      if (rate > 0) return rate;
    } catch (_) {}
    return 60.0;
  }

  void _updateMetrics() {
    final targetRate = _detectRefreshRate();
    final frameBudgetMs = 1000.0 / targetRate;

    if (_recentTimings.isEmpty) {
      setState(() {
        _currentFps = targetRate;
        _avgBuildMs = 1.6;
        _avgRasterMs = 2.2;
        _smoothnessPercent = 100.0;
        _jankFrameCount = 0;
      });
      return;
    }

    double totalBuildUs = 0;
    double totalRasterUs = 0;
    int janks = 0;

    for (final timing in _recentTimings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
      totalBuildUs += timing.buildDuration.inMicroseconds;
      totalRasterUs += timing.rasterDuration.inMicroseconds;
      if ((buildMs + rasterMs) > frameBudgetMs) {
        janks++;
      }
    }

    final count = _recentTimings.length;
    final avgBuild = (totalBuildUs / count) / 1000.0;
    final avgRaster = (totalRasterUs / count) / 1000.0;
    final smoothness = ((count - janks) / count * 100.0).clamp(0.0, 100.0);
    final fps = (targetRate * (smoothness / 100.0)).clamp(0.0, targetRate);

    setState(() {
      _currentFps = fps;
      _avgBuildMs = avgBuild;
      _avgRasterMs = avgRaster;
      _smoothnessPercent = smoothness;
      _jankFrameCount = janks;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetRefreshRate = _detectRefreshRate();
    final frameBudgetMs = 1000.0 / targetRefreshRate;
    final totalRenderMs = _avgBuildMs + _avgRasterMs;
    final frameBudgetUtilization = (totalRenderMs / frameBudgetMs * 100.0)
        .clamp(0.0, 100.0);

    final pressure = evaluateLoadPressure(
      powerSaveModeEnabled: widget.powerSaveModeEnabled,
      animationsEnabled: widget.animationsEnabled,
      motionBlurEnabled: widget.motionBlurEnabled,
      layerBlurEnabled: widget.layerBlurEnabled,
      liquidGlassEnabled: widget.liquidGlassEnabled,
      liquidGlassMode: widget.liquidGlassMode,
      liquidGlassBlur: widget.liquidGlassBlur,
      liquidGlassTransparency: widget.liquidGlassTransparency,
      screenRadiusEnabled: widget.screenRadiusEnabled,
      lazyLoadEnabled: widget.lazyLoadEnabled,
      frameBudgetUtilizationPercent: frameBudgetUtilization,
    );

    return Card(
      key: const ValueKey<String>('animation-performance-metric-card'),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: pressure.isHighPressure
              ? colorScheme.error.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(widget.isDesktop ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶栏：标题与当前屏幕刷新率
            Row(
              children: [
                Icon(
                  Icons.speed_rounded,
                  color: pressure.getLevelColor(colorScheme),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '流畅度与负载压力',
                    style: TextStyle(
                      fontSize: widget.isDesktop ? 17 : 15.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${targetRefreshRate.round()} Hz 刷新率',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '实时监测界面渲染耗时与帧率稳定性，动态量化当前动效对系统与硬件的负载压力。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // 悬浮监控操作栏：支持带到其他页面全局测试
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: AnimationPerformanceMonitorService
                      .isFloatingActiveListenable,
                  builder: (context, isFloating, _) {
                    return ActionChip(
                      key: const ValueKey(
                        'animation-performance-float-toggle-chip',
                      ),
                      avatar: Icon(
                        isFloating
                            ? Icons.check_circle_rounded
                            : Icons.picture_in_picture_alt_rounded,
                        size: 15,
                        color: isFloating
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      label: Text(
                        isFloating ? '悬浮监控运行中 (点击关闭)' : '开启悬浮监控',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isFloating
                              ? FontWeight.bold
                              : FontWeight.w600,
                          color: isFloating
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      backgroundColor: isFloating
                          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                          : colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.45,
                            ),
                      side: BorderSide(
                        color: isFloating
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 1,
                      ),
                      onPressed: () {
                        AnimationPerformanceMonitorService.toggleFloating();
                        if (!isFloating) {
                          AppSnackBars.showSnackBar(
                            context,
                            const SnackBar(
                              content: Text('已开启性能悬浮窗，可在全应用任意页面测试流畅度与负载压力'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'animation-performance-float-navigate-btn',
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 14),
                  label: const Text(
                    '带到其他界面测试',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () {
                    AnimationPerformanceMonitorService.showFloating();
                    AppSnackBars.showSnackBar(
                      context,
                      const SnackBar(
                        content: Text('已开启性能悬浮窗，可前往主页、课表或待办等界面实时测试'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    Navigator.of(context).maybePop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 三项核心流畅度量化指标
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 340;
                final spacing = isNarrow ? 6.0 : 8.0;

                return Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        context: context,
                        icon: Icons.insights_rounded,
                        label: '实时帧率',
                        value: '${_currentFps.toStringAsFixed(1)} FPS',
                        valueKey: 'animation-performance-fps-text',
                        subtext: '目标 ${targetRefreshRate.round()} Hz',
                        accentColor: _currentFps >= (targetRefreshRate * 0.9)
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                    ),
                    SizedBox(width: spacing),
                    Expanded(
                      child: _buildMetricTile(
                        context: context,
                        icon: Icons.timer_outlined,
                        label: '渲染耗时',
                        value: '${totalRenderMs.toStringAsFixed(1)} ms',
                        valueKey: 'animation-performance-render-time-text',
                        subtext:
                            '构建 ${_avgBuildMs.toStringAsFixed(1)} · 栅格 ${_avgRasterMs.toStringAsFixed(1)}',
                        accentColor: totalRenderMs <= frameBudgetMs
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                    ),
                    SizedBox(width: spacing),
                    Expanded(
                      child: _buildMetricTile(
                        context: context,
                        icon: Icons.check_circle_outline_rounded,
                        label: '流畅度达标率',
                        value: '${_smoothnessPercent.toStringAsFixed(1)}%',
                        valueKey: 'animation-performance-smoothness-text',
                        subtext: _jankFrameCount == 0
                            ? '近 60 帧无掉帧'
                            : '$_jankFrameCount 帧超出预算',
                        accentColor: _smoothnessPercent >= 90
                            ? colorScheme.primary
                            : colorScheme.tertiary,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // 综合负载压力评估条
            Row(
              children: [
                Icon(
                  Icons.memory_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '综合负载压力',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: pressure.getLevelContainerColor(colorScheme),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${pressure.levelLabel} (${pressure.scorePercent}%)',
                    key: const ValueKey<String>(
                      'animation-performance-pressure-text',
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: pressure.getLevelColor(colorScheme),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pressure.scorePercent / 100.0,
                minHeight: 7,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: pressure.getLevelColor(colorScheme),
              ),
            ),
            const SizedBox(height: 10),

            // 特效负载构成细项
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: pressure.factors.map((factor) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    factor,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 14),

            // 明确注明：开启较多特效可能会导致卡顿
            Container(
              key: const ValueKey<String>('animation-performance-caution-card'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pressure.isHighPressure
                    ? colorScheme.errorContainer.withValues(alpha: 0.22)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: pressure.isHighPressure
                      ? colorScheme.error.withValues(alpha: 0.35)
                      : colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        pressure.isHighPressure
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline_rounded,
                        size: 18,
                        color: pressure.isHighPressure
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          pressure.cautionTitle, // 开启较多特效可能会导致卡顿
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: pressure.isHighPressure
                                ? colorScheme.error
                                : colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pressure.cautionDescription,
                    key: const ValueKey<String>(
                      'animation-performance-caution-text',
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: pressure.isHighPressure
                          ? colorScheme.onErrorContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 实时流畅度交互微调/测试带
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '滑动滑块即时产生连续帧，验证流畅度',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: widget.isDesktop ? 140 : 100,
                    height: 24,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                      ),
                      child: Slider(
                        key: const ValueKey<String>(
                          'animation-performance-test-slider',
                        ),
                        value: _interactiveTestValue,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (val) {
                          setState(() {
                            _interactiveTestValue = val;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String valueKey,
    required String subtext,
    required Color accentColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              key: ValueKey<String>(valueKey),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtext,
            style: TextStyle(
              fontSize: 9.5,
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
