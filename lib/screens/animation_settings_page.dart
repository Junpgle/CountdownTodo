import 'dart:async';

import 'package:flutter/material.dart';

import '../services/animation_config_service.dart';
import '../services/liquid_glass_effect_service.dart';
import '../services/power_save_mode_service.dart';
import '../utils/app_image_filters.dart';
import '../utils/app_platform.dart';
import '../utils/page_transitions.dart';
import '../widgets/animation_performance_metric_card.dart';
import '../widgets/settings_toggle_card.dart';
import '../widgets/floating_glass_control.dart';
import '../utils/app_dialogs.dart';

part 'animation_settings/animation_settings_view.dart';
part 'animation_settings/animation_settings_widgets.dart';

class AnimationSettingsPage extends StatefulWidget {
  final bool isEmbedded;
  final String? initialTarget;

  /// Allows widget tests to exercise Android's transient system override on
  /// non-Android hosts. Production callers should leave this unset.
  @visibleForTesting
  final bool? powerSaveModeOverride;

  const AnimationSettingsPage({
    super.key,
    this.isEmbedded = false,
    this.initialTarget,
    this.powerSaveModeOverride,
  });

  @override
  State<AnimationSettingsPage> createState() => _AnimationSettingsPageState();
}

class _AnimationSettingsPageState extends State<AnimationSettingsPage> {
  final _scrollController = ScrollController();
  final _glassKey = GlobalKey();
  final _transparencyKey = GlobalKey();
  String? _highlightTarget;
  Timer? _highlightTimer;
  bool _initialTargetRevealed = false;

  Future<void> _revealInitialTarget() async {
    final target = widget.initialTarget;
    final key = switch (target) {
      'liquid_glass' => _glassKey,
      'liquid_glass_transparency' => _transparencyKey,
      _ => null,
    };
    if (key == null || _initialTargetRevealed) return;
    _initialTargetRevealed = true;
    // ListView creates off-screen children lazily. Advance until the target
    // exists, then align the exact control after async settings have loaded.
    for (var attempt = 0; attempt < 24 && mounted; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      final targetContext = key.currentContext;
      if (targetContext != null && targetContext.mounted) {
        setState(() => _highlightTarget = target);
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.2,
          duration: const Duration(milliseconds: 350),
        );
        if (!mounted) return;
        _highlightTimer?.cancel();
        _highlightTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _highlightTarget = null);
        });
        return;
      }
      final position = _scrollController.position;
      _scrollController.jumpTo(
        (position.pixels + position.viewportDimension * 0.8).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  bool _animationsEnabled = true;
  bool _motionBlurEnabled = false;
  bool _layerBlurEnabled = false;
  bool _liquidGlassEnabled = false;
  LiquidGlassEffectMode _liquidGlassMode = LiquidGlassEffectMode.standard;
  int _liquidGlassTransparency =
      LiquidGlassEffectConfiguration.defaultTransparencyPercent;
  int _liquidGlassScrimCoverage =
      LiquidGlassEffectConfiguration.defaultScrimCoveragePercent;
  double _liquidGlassBlur = LiquidGlassEffectConfiguration.defaultBlurSigma;
  bool _liquidGlassMutationPending = false;
  bool _lazyLoadEnabled = true;
  bool _skeletonScreenEnabled = true;
  bool _screenRadiusEnabled = true;
  bool _predictiveBackEnabled = true;
  int _animationDuration = AnimationSpeedPreset.elegant.duration;
  int _pageLayerDepth = 18;
  int _containerContentStart = 12;
  AnimationPreset? _preset = AnimationPreset.balanced;
  AnimationSpeedPreset? _speedPreset = AnimationSpeedPreset.elegant;

  bool get _powerSaveModeEnabled =>
      widget.powerSaveModeOverride ?? PowerSaveModeService.isEnabled;

  String get _liquidGlassModeDescription {
    if (AppPlatform.isWindows) {
      return '默认不启用模糊。开启 Liquid Glass 后使用标准玻璃与模糊效果；增强模式在 Windows 上不可用。';
    }
    return _liquidGlassMode == LiquidGlassEffectMode.standard
        ? '高可读性和低功耗；滚动卡片使用轻量玻璃材质，重点表面保留折射。'
        : '更强折射、高光和色散；固定重点表面使用高画质玻璃，滚动卡片启用实时玻璃。';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        LiquidGlassEffectService.isSettingsPageActive = true;
      }
    });
    if (widget.powerSaveModeOverride == null) {
      PowerSaveModeService.enabledListenable.addListener(
        _handlePowerSaveModeChanged,
      );
    }
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant AnimationSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.powerSaveModeOverride == widget.powerSaveModeOverride) return;
    if (oldWidget.powerSaveModeOverride == null) {
      PowerSaveModeService.enabledListenable.removeListener(
        _handlePowerSaveModeChanged,
      );
    }
    if (widget.powerSaveModeOverride == null) {
      PowerSaveModeService.enabledListenable.addListener(
        _handlePowerSaveModeChanged,
      );
    }
  }

  @override
  void dispose() {
    LiquidGlassEffectService.isSettingsPageActive = false;
    _highlightTimer?.cancel();
    _scrollController.dispose();
    if (widget.powerSaveModeOverride == null) {
      PowerSaveModeService.enabledListenable.removeListener(
        _handlePowerSaveModeChanged,
      );
    }
    super.dispose();
  }

  void _handlePowerSaveModeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait([
      AnimationConfigService.isAnimationsEnabled(),
      AnimationConfigService.isMotionBlurEnabled(),
      AnimationConfigService.isLayerBlurEnabled(),
      AnimationConfigService.isLazyLoadEnabled(),
      AnimationConfigService.isSkeletonScreenEnabled(),
      AnimationConfigService.isScreenRadiusEnabled(),
      AnimationConfigService.isPredictiveBackEnabled(),
      AnimationConfigService.getAnimationDuration(),
      AnimationConfigService.getPageLayerDepth(),
      AnimationConfigService.getContainerContentStart(),
      AnimationConfigService.getPreset(),
      AnimationConfigService.getAnimationSpeedPreset(),
      LiquidGlassEffectService.loadConfiguration(),
    ]);
    if (!mounted) return;
    setState(() {
      _animationsEnabled = results[0] as bool;
      _motionBlurEnabled = results[1] as bool;
      _layerBlurEnabled = results[2] as bool;
      _lazyLoadEnabled = results[3] as bool;
      _skeletonScreenEnabled = results[4] as bool;
      _screenRadiusEnabled = results[5] as bool;
      _predictiveBackEnabled = results[6] as bool;
      _animationDuration = results[7] as int;
      _pageLayerDepth = results[8] as int;
      _containerContentStart = results[9] as int;
      _preset = results[10] as AnimationPreset?;
      _speedPreset = results[11] as AnimationSpeedPreset?;
      final liquidGlass = results[12] as LiquidGlassEffectConfiguration;
      _liquidGlassEnabled = liquidGlass.enabled;
      _liquidGlassMode = liquidGlass.mode;
      _liquidGlassTransparency = liquidGlass.transparencyPercent;
      _liquidGlassScrimCoverage = liquidGlass.scrimCoveragePercent;
      _liquidGlassBlur = liquidGlass.blurSigma;
    });
    unawaited(_revealInitialTarget());
  }

  Future<void> _setLiquidGlassEnabled(bool enabled) async {
    if (_liquidGlassMutationPending) return;
    final previous = _liquidGlassEnabled;
    setState(() {
      _liquidGlassEnabled = enabled;
      _liquidGlassMutationPending = true;
    });
    try {
      await LiquidGlassEffectService.setEnabled(enabled);
      await AnimationConfigService.clearActivePreset();
      if (mounted) setState(() => _preset = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _liquidGlassEnabled = previous);
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('Liquid Glass 初始化失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _liquidGlassMutationPending = false);
      }
    }
  }

  Future<void> _setLiquidGlassMode(LiquidGlassEffectMode mode) async {
    if (_liquidGlassMutationPending) return;
    final previous = _liquidGlassMode;
    setState(() {
      _liquidGlassMode = mode;
      _liquidGlassMutationPending = true;
    });
    try {
      await LiquidGlassEffectService.setMode(mode);
      await AnimationConfigService.clearActivePreset();
      if (mounted) setState(() => _preset = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _liquidGlassMode = previous);
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('Liquid Glass 模式切换失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _liquidGlassMutationPending = false);
      }
    }
  }

  void _updateLiquidGlassAdjustments({
    int? scrimCoverage,
    int? transparency,
    double? blur,
  }) {
    final nextScrim = scrimCoverage ?? _liquidGlassScrimCoverage;
    final nextTransparency = transparency ?? _liquidGlassTransparency;
    final nextBlur = blur ?? _liquidGlassBlur;

    setState(() {
      _liquidGlassScrimCoverage = nextScrim;
      _liquidGlassTransparency = nextTransparency;
      _liquidGlassBlur = nextBlur;
    });

    LiquidGlassEffectService.previewAdjustments(
      scrimCoveragePercent: nextScrim,
      transparencyPercent: nextTransparency,
      blurSigma: nextBlur,
    );
  }

  Future<void> _saveLiquidGlassAdjustments() async {
    try {
      await LiquidGlassEffectService.saveAdjustments();
      await AnimationConfigService.clearActivePreset();
      if (mounted) {
        setState(() => _preset = null);
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('已保存 Liquid Glass 效果设置')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('保存失败：$error')),
      );
    }
  }

  Future<void> _applyPreset(AnimationPreset preset) async {
    setState(() => _preset = preset);
    await AnimationConfigService.setPreset(preset);
    await PageTransitions.init();
    await _loadSettings();
  }

  Future<void> _applySpeedPreset(AnimationSpeedPreset preset) async {
    setState(() {
      _speedPreset = preset;
      _animationDuration = preset.duration;
      _preset = null;
    });
    await AnimationConfigService.setAnimationSpeedPreset(preset);
    await PageTransitions.init();
  }

  Future<void> _update({
    bool? enabled,
    bool? motionBlur,
    bool? layerBlur,
    bool? lazyLoad,
    bool? skeletonScreen,
    bool? screenRadius,
    bool? predictiveBack,
    int? duration,
    int? pageLayerDepth,
    int? containerContentStart,
  }) async {
    if (_preset != null && mounted) {
      setState(() => _preset = null);
    }
    if (enabled != null) {
      await AnimationConfigService.setAnimationsEnabled(enabled);
    }
    if (motionBlur != null) {
      await AnimationConfigService.setMotionBlurEnabled(motionBlur);
    }
    if (layerBlur != null) {
      await AnimationConfigService.setLayerBlurEnabled(layerBlur);
    }
    if (lazyLoad != null) {
      await AnimationConfigService.setLazyLoadEnabled(lazyLoad);
    }
    if (skeletonScreen != null) {
      await AnimationConfigService.setSkeletonScreenEnabled(skeletonScreen);
    }
    if (screenRadius != null) {
      await AnimationConfigService.setScreenRadiusEnabled(screenRadius);
    }
    if (predictiveBack != null) {
      await AnimationConfigService.setPredictiveBackEnabled(predictiveBack);
    }
    if (duration != null) {
      if (mounted) setState(() => _speedPreset = null);
      await AnimationConfigService.setAnimationDuration(duration);
    }
    if (pageLayerDepth != null) {
      await AnimationConfigService.setPageLayerDepth(pageLayerDepth);
    }
    if (containerContentStart != null) {
      await AnimationConfigService.setContainerContentStart(
        containerContentStart,
      );
    }
    await PageTransitions.init();
  }

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) => _buildSettingsScaffold(context);
}
