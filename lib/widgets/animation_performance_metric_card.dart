import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/liquid_glass_effect_service.dart';

/// 渲染压力评估结果
class RenderingPressureEvaluation {
  const RenderingPressureEvaluation({
    required this.scorePercent,
    required this.levelLabel,
    required this.factors,
    required this.cautionTitle,
    required this.cautionDescription,
    required this.isHighPressure,
  });

  /// 综合渲染压力得分 (0 - 100)
  final int scorePercent;

  /// 压力等级描述 (极低、轻度、适中、较高、极高)
  final String levelLabel;

  /// 激活的渲染负载细项
  final List<String> factors;

  /// 警示标题
  final String cautionTitle;

  /// 详细说明与建议
  final String cautionDescription;

  /// 是否属于较高或重度渲染压力
  final bool isHighPressure;

  /// 依据主题色彩规范获取等级指示色
  Color getLevelColor(ColorScheme colorScheme) {
    if (scorePercent <= 28) {
      return colorScheme.primary;
    } else if (scorePercent <= 52) {
      return colorScheme.secondary;
    } else if (scorePercent <= 74) {
      return colorScheme.tertiary;
    } else {
      return colorScheme.error;
    }
  }

  /// 依据主题色彩规范获取背景容器色
  Color getLevelContainerColor(ColorScheme colorScheme) {
    if (scorePercent <= 28) {
      return colorScheme.primaryContainer;
    } else if (scorePercent <= 52) {
      return colorScheme.secondaryContainer;
    } else if (scorePercent <= 74) {
      return colorScheme.tertiaryContainer;
    } else {
      return colorScheme.errorContainer;
    }
  }
}

/// 计算当前特效配置下的渲染压力量化评估
RenderingPressureEvaluation evaluateRenderingPressure({
  required bool powerSaveModeEnabled,
  required bool animationsEnabled,
  required bool motionBlurEnabled,
  required bool layerBlurEnabled,
  required bool liquidGlassEnabled,
  required LiquidGlassEffectMode liquidGlassMode,
  required double liquidGlassBlur,
  required int liquidGlassTransparency,
  required bool screenRadiusEnabled,
  required bool lazyLoadEnabled,
  double? frameBudgetUtilizationPercent,
}) {
  if (powerSaveModeEnabled) {
    return const RenderingPressureEvaluation(
      scorePercent: 12,
      levelLabel: '极低',
      factors: ['系统省电模式已介入 (全应用装饰特效已暂停)', '渲染负荷已压至最低'],
      cautionTitle: '开启较多特效可能会导致卡顿',
      cautionDescription: '当前处于系统省电模式，已自动限制高开销动效与玻璃折射以降低功耗。退出省电模式后将自动恢复原设定。',
      isHighPressure: false,
    );
  }

  int staticScore = 6; // Flutter 引擎基准开销
  final factors = <String>[];

  if (animationsEnabled) {
    staticScore += 10;
    factors.add('页面转场动画 (+10%)');
  } else {
    factors.add('转场动画已关闭 (0%)');
  }

  if (motionBlurEnabled) {
    staticScore += 26;
    factors.add('运动模糊 (+26% 动态插值开销)');
  }

  if (layerBlurEnabled) {
    staticScore += 24;
    factors.add('层级模糊 (+24% GPU背景滤镜开销)');
  }

  if (liquidGlassEnabled) {
    if (liquidGlassMode == LiquidGlassEffectMode.enhanced) {
      staticScore += 34;
      factors.add('Liquid Glass 增强模式 (+34% 折射高光)');
    } else {
      staticScore += 20;
      factors.add('Liquid Glass 标准模式 (+20% 玻璃材质)');
    }
    if (liquidGlassBlur > 14) {
      staticScore += 8;
      factors.add('深度磨砂 (${liquidGlassBlur.round()}px, +8%)');
    }
  }

  if (screenRadiusEnabled) {
    staticScore += 8;
    factors.add('屏幕圆角裁切 (+8%)');
  }

  if (!lazyLoadEnabled) {
    staticScore += 15;
    factors.add('关闭懒加载 (+15% 突发开销)');
  } else {
    factors.add('懒加载优化已开启 (削峰填谷)');
  }

  // 结合实测帧预算占用率微调压力指数
  double combinedScore = staticScore.toDouble();
  if (frameBudgetUtilizationPercent != null &&
      frameBudgetUtilizationPercent > 0) {
    combinedScore = staticScore * 0.75 + frameBudgetUtilizationPercent * 0.25;
  }
  final clampedScore = combinedScore.round().clamp(6, 100);

  final String levelLabel;
  final bool isHighPressure;
  final String cautionDesc;

  if (clampedScore <= 28) {
    levelLabel = '极低';
    isHighPressure = false;
    cautionDesc = '当前渲染压力极低，各特效负担轻微，适合任何设备或长续航场景。请注意：若后续开启较多高级特效，渲染压力将随之增加。';
  } else if (clampedScore <= 52) {
    levelLabel = '轻度';
    isHighPressure = false;
    cautionDesc = '当前渲染压力适中偏低，可在绝大多数现代设备上保持稳定满帧。开启较多高负载特效可能会导致低配设备卡顿。';
  } else if (clampedScore <= 74) {
    levelLabel = '适中';
    isHighPressure = false;
    cautionDesc = '当前启用了部分视觉特效，视觉表现丰富。若在部分中低端设备或高刷新率屏幕上遇到滑动掉帧，可适当调减模糊或玻璃特效。';
  } else if (clampedScore <= 88) {
    levelLabel = '较高';
    isHighPressure = true;
    cautionDesc = '已开启较多高负载特效（如 Liquid Glass、模糊效果等）。在高分屏或 120Hz 刷新率下可能导致 GPU 渲染负载过重出现掉帧与发热，中低端设备建议选用「平衡」预设。';
  } else {
    levelLabel = '极高';
    isHighPressure = true;
    cautionDesc = '多项重度渲染特效同时处于开启状态，GPU 渲染与图层混合处于满载边缘，中低端机型极易出现明显卡顿、发热与掉帧。强烈建议关闭部分高耗特效或切换至「性能」预设。';
  }

  return RenderingPressureEvaluation(
    scorePercent: clampedScore,
    levelLabel: levelLabel,
    factors: factors,
    cautionTitle: '开启较多特效可能会导致卡顿',
    cautionDescription: cautionDesc,
    isHighPressure: isHighPressure,
  );
}

/// 动画与特效设置顶部的流畅度量化指标与渲染压力仪表卡片
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

    final pressure = evaluateRenderingPressure(
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
                    '流畅度与渲染压力',
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
              '实时监测界面渲染耗时与帧率稳定性，动态量化当前动效对 GPU/CPU 的压力。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

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

            // 综合渲染压力评估条
            Row(
              children: [
                Icon(
                  Icons.memory_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '综合渲染压力',
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
