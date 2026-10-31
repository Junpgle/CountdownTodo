import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'animation_config_service.dart';
import 'liquid_glass_effect_service.dart';
import 'power_save_mode_service.dart';

/// 负载压力评估结果模型
class LoadPressureEvaluation {
  const LoadPressureEvaluation({
    required this.scorePercent,
    required this.levelLabel,
    required this.factors,
    required this.cautionTitle,
    required this.cautionDescription,
    required this.isHighPressure,
  });

  /// 综合负载压力得分 (0 - 100)
  final int scorePercent;

  /// 压力等级描述 (极低、轻度、适中、较高、极高)
  final String levelLabel;

  /// 激活的动效负载细项
  final List<String> factors;

  /// 警示标题
  final String cautionTitle;

  /// 详细说明与建议
  final String cautionDescription;

  /// 是否属于较高或重度负载压力
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

/// 兼容别名
typedef RenderingPressureEvaluation = LoadPressureEvaluation;

/// 计算特定特效配置下的综合负载压力量化评估
LoadPressureEvaluation evaluateLoadPressure({
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
    return const LoadPressureEvaluation(
      scorePercent: 12,
      levelLabel: '极低',
      factors: ['系统省电模式已介入 (全应用装饰特效已暂停)', '综合负载已压至最低'],
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
    cautionDesc = '当前负载压力极低，各特效负担轻微，适合任何设备或长续航场景。请注意：若后续开启较多高级特效，负载压力将随之增加。';
  } else if (clampedScore <= 52) {
    levelLabel = '轻度';
    isHighPressure = false;
    cautionDesc = '当前负载压力适中偏低，可在绝大多数现代设备上保持稳定满帧。开启较多高负载特效可能会导致低配设备卡顿。';
  } else if (clampedScore <= 74) {
    levelLabel = '适中';
    isHighPressure = false;
    cautionDesc = '当前启用了部分视觉特效，视觉表现丰富。若在部分中低端设备或高刷新率屏幕上遇到滑动掉帧，可适当调减模糊或玻璃特效。';
  } else if (clampedScore <= 88) {
    levelLabel = '较高';
    isHighPressure = true;
    cautionDesc = '已开启较多高负载特效（如 Liquid Glass、模糊效果等）。在高分屏或 120Hz 刷新率下可能导致 CPU/GPU 负载过重出现掉帧与发热，中低端设备建议选用「平衡」预设。';
  } else {
    levelLabel = '极高';
    isHighPressure = true;
    cautionDesc = '多项重度动效与渲染特效同时处于开启状态，系统负载与图层混合处于满载边缘，中低端机型极易出现明显卡顿、发热与掉帧。强烈建议关闭部分高耗特效或切换至「性能」预设。';
  }

  return LoadPressureEvaluation(
    scorePercent: clampedScore,
    levelLabel: levelLabel,
    factors: factors,
    cautionTitle: '开启较多特效可能会导致卡顿',
    cautionDescription: cautionDesc,
    isHighPressure: isHighPressure,
  );
}

/// 兼容别名方法
@Deprecated('Use evaluateLoadPressure instead')
LoadPressureEvaluation evaluateRenderingPressure({
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
}) => evaluateLoadPressure(
  powerSaveModeEnabled: powerSaveModeEnabled,
  animationsEnabled: animationsEnabled,
  motionBlurEnabled: motionBlurEnabled,
  layerBlurEnabled: layerBlurEnabled,
  liquidGlassEnabled: liquidGlassEnabled,
  liquidGlassMode: liquidGlassMode,
  liquidGlassBlur: liquidGlassBlur,
  liquidGlassTransparency: liquidGlassTransparency,
  screenRadiusEnabled: screenRadiusEnabled,
  lazyLoadEnabled: lazyLoadEnabled,
  frameBudgetUtilizationPercent: frameBudgetUtilizationPercent,
);

/// 性能度量实时快照
class PerformanceMetricsSnapshot {
  const PerformanceMetricsSnapshot({
    required this.currentFps,
    required this.targetRefreshRate,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.totalRenderMs,
    required this.smoothnessPercent,
    required this.jankCount,
    required this.frameBudgetMs,
    required this.frameBudgetUtilization,
  });

  const PerformanceMetricsSnapshot.empty({double targetRefreshRate = 60.0})
    : currentFps = targetRefreshRate,
      targetRefreshRate = targetRefreshRate,
      avgBuildMs = 1.6,
      avgRasterMs = 2.2,
      totalRenderMs = 3.8,
      smoothnessPercent = 100.0,
      jankCount = 0,
      frameBudgetMs = 1000.0 / targetRefreshRate,
      frameBudgetUtilization = 3.8 / (1000.0 / targetRefreshRate) * 100.0;

  final double currentFps;
  final double targetRefreshRate;
  final double avgBuildMs;
  final double avgRasterMs;
  final double totalRenderMs;
  final double smoothnessPercent;
  final int jankCount;
  final double frameBudgetMs;
  final double frameBudgetUtilization;
}

/// 全局动画与流畅度监控服务（支持页面内仪表与全局悬浮窗）
class AnimationPerformanceMonitorService {
  AnimationPerformanceMonitorService._();

  static final ValueNotifier<bool> isFloatingActiveListenable =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isExpandedListenable = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<PerformanceMetricsSnapshot> metricsListenable =
      ValueNotifier<PerformanceMetricsSnapshot>(
        const PerformanceMetricsSnapshot.empty(),
      );

  static bool get isFloatingActive => isFloatingActiveListenable.value;
  static bool get isExpanded => isExpandedListenable.value;
  static PerformanceMetricsSnapshot get currentSnapshot =>
      metricsListenable.value;

  static const int _maxFrameWindow = 60;
  static final List<FrameTiming> _recentTimings = [];
  static Timer? _refreshTimer;
  static bool _isCallbackRegistered = false;
  static int _consumerCount = 0;

  // 缓存的特效配置
  static bool _animationsEnabled = true;
  static bool _motionBlurEnabled = false;
  static bool _layerBlurEnabled = false;
  static bool _screenRadiusEnabled = true;
  static bool _lazyLoadEnabled = true;

  @visibleForTesting
  static double? testRefreshRate;

  @visibleForTesting
  static bool enablePeriodicTimer = true;

  static bool _listenersAttached = false;

  static void _ensureExternalListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    LiquidGlassEffectService.configurationListenable.addListener(
      _handleConfigChanged,
    );
    PowerSaveModeService.enabledListenable.addListener(_handleConfigChanged);
  }

  static void _handleConfigChanged() {
    unawaited(refreshConfig());
  }

  /// 开启悬浮窗监控
  static void showFloating({bool expand = false}) {
    _ensureExternalListeners();
    isExpandedListenable.value = expand;
    isFloatingActiveListenable.value = true;
    _startTimingsIfNeeded();
    unawaited(refreshConfig());
  }

  /// 关闭悬浮窗监控
  static void hideFloating() {
    isFloatingActiveListenable.value = false;
    if (_consumerCount == 0) {
      _stopTimings();
    }
  }

  /// 切换悬浮窗开关
  static void toggleFloating() {
    if (isFloatingActive) {
      hideFloating();
    } else {
      showFloating();
    }
  }

  /// 设置悬浮窗展开/收起状态
  static void setExpanded(bool expanded) {
    isExpandedListenable.value = expanded;
  }

  /// 切换悬浮窗展开/收起
  static void toggleExpanded() {
    isExpandedListenable.value = !isExpandedListenable.value;
  }

  /// 页面（如动画设置页）挂载时注册监听
  static void registerConsumer() {
    _ensureExternalListeners();
    _consumerCount++;
    _startTimingsIfNeeded();
    unawaited(refreshConfig());
  }

  /// 页面卸载时注销
  static void unregisterConsumer() {
    _consumerCount = (_consumerCount - 1).clamp(0, 9999);
    if (_consumerCount == 0 && !isFloatingActive) {
      _stopTimings();
    }
  }

  /// 异步刷新当前特效配置缓存
  static Future<void> refreshConfig() async {
    try {
      final results = await Future.wait([
        AnimationConfigService.isAnimationsEnabled(),
        AnimationConfigService.isMotionBlurEnabled(),
        AnimationConfigService.isLayerBlurEnabled(),
        AnimationConfigService.isScreenRadiusEnabled(),
        AnimationConfigService.isLazyLoadEnabled(),
      ]);
      _animationsEnabled = results[0];
      _motionBlurEnabled = results[1];
      _layerBlurEnabled = results[2];
      _screenRadiusEnabled = results[3];
      _lazyLoadEnabled = results[4];
      _computeAndNotifyMetrics();
    } catch (_) {}
  }

  static void _startTimingsIfNeeded() {
    if (_isCallbackRegistered) return;
    _isCallbackRegistered = true;
    try {
      SchedulerBinding.instance.addTimingsCallback(_handleTimings);
    } catch (_) {}
    _refreshTimer?.cancel();
    if (enablePeriodicTimer) {
      _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _computeAndNotifyMetrics();
      });
    }
  }

  static void _stopTimings() {
    if (!_isCallbackRegistered) return;
    _isCallbackRegistered = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    try {
      SchedulerBinding.instance.removeTimingsCallback(_handleTimings);
    } catch (_) {}
    _recentTimings.clear();
  }

  static void _handleTimings(List<FrameTiming> timings) {
    _recentTimings.addAll(timings);
    if (_recentTimings.length > _maxFrameWindow) {
      _recentTimings.removeRange(0, _recentTimings.length - _maxFrameWindow);
    }
  }

  /// 估算或读取当前显示刷新率
  static double detectRefreshRate([BuildContext? context]) {
    if (testRefreshRate != null && testRefreshRate! > 0) {
      return testRefreshRate!;
    }
    if (context != null) {
      try {
        final rate = View.of(context).display.refreshRate;
        if (rate > 0) return rate;
      } catch (_) {}
    }
    return 60.0;
  }

  static void _computeAndNotifyMetrics() {
    final targetRate = detectRefreshRate();
    final frameBudgetMs = 1000.0 / targetRate;

    if (_recentTimings.isEmpty) {
      final defaultSnapshot = PerformanceMetricsSnapshot.empty(
        targetRefreshRate: targetRate,
      );
      metricsListenable.value = defaultSnapshot;
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
    final totalRender = avgBuild + avgRaster;
    final smoothness = ((count - janks) / count * 100.0).clamp(0.0, 100.0);
    final fps = (targetRate * (smoothness / 100.0)).clamp(0.0, targetRate);
    final utilization = (totalRender / frameBudgetMs * 100.0).clamp(0.0, 100.0);

    metricsListenable.value = PerformanceMetricsSnapshot(
      currentFps: fps,
      targetRefreshRate: targetRate,
      avgBuildMs: avgBuild,
      avgRasterMs: avgRaster,
      totalRenderMs: totalRender,
      smoothnessPercent: smoothness,
      jankCount: janks,
      frameBudgetMs: frameBudgetMs,
      frameBudgetUtilization: utilization,
    );
  }

  /// 获取当前全应用实际生效配置下的综合负载压力评估
  static LoadPressureEvaluation evaluateCurrentPressure() {
    final liquidGlassConfig = LiquidGlassEffectService.configuration;
    final powerSave = PowerSaveModeService.isEnabled;

    return evaluateLoadPressure(
      powerSaveModeEnabled: powerSave,
      animationsEnabled: _animationsEnabled && !powerSave,
      motionBlurEnabled: _motionBlurEnabled && !powerSave,
      layerBlurEnabled: _layerBlurEnabled && !powerSave,
      liquidGlassEnabled: liquidGlassConfig.enabled && !powerSave,
      liquidGlassMode: liquidGlassConfig.mode,
      liquidGlassBlur: liquidGlassConfig.blurSigma,
      liquidGlassTransparency: liquidGlassConfig.transparencyPercent,
      screenRadiusEnabled: _screenRadiusEnabled && !powerSave,
      lazyLoadEnabled: _lazyLoadEnabled,
      frameBudgetUtilizationPercent:
          metricsListenable.value.frameBudgetUtilization,
    );
  }

  /// 测试方法：注入帧耗时以供验证
  @visibleForTesting
  static void recordTimingsForTesting(List<FrameTiming> timings) {
    _handleTimings(timings);
    _computeAndNotifyMetrics();
  }

  /// 测试方法：重置内部状态
  @visibleForTesting
  static void resetForTesting() {
    _stopTimings();
    _consumerCount = 0;
    testRefreshRate = null;
    enablePeriodicTimer = false;
    isFloatingActiveListenable.value = false;
    isExpandedListenable.value = false;
    metricsListenable.value = const PerformanceMetricsSnapshot.empty();
  }
}
