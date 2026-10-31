import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/animation_config_service.dart';
import '../services/liquid_glass_effect_service.dart';
import '../services/power_save_mode_service.dart';
import '../utils/app_platform.dart';
import '../utils/page_transitions.dart';
import '../widgets/settings_toggle_card.dart';
import '../widgets/floating_glass_control.dart';
import '../utils/app_dialogs.dart';

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
      return _liquidGlassMode == LiquidGlassEffectMode.standard
          ? '高可读性和低功耗；Windows 使用静态半透明材质，避免重复背景模糊。'
          : '增强材质层次与高光；Windows 使用静态玻璃和标准渲染，避免实时模糊拖慢动画。';
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
      _screenRadiusEnabled = results[4] as bool;
      _predictiveBackEnabled = results[5] as bool;
      _animationDuration = results[6] as int;
      _pageLayerDepth = results[7] as int;
      _containerContentStart = results[8] as int;
      _preset = results[9] as AnimationPreset?;
      _speedPreset = results[10] as AnimationSpeedPreset?;
      final liquidGlass = results[11] as LiquidGlassEffectConfiguration;
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final powerSaveModeEnabled = _powerSaveModeEnabled;
    final effectiveAnimationsEnabled =
        _animationsEnabled && !powerSaveModeEnabled;
    final effectiveScreenRadiusEnabled =
        _screenRadiusEnabled && !powerSaveModeEnabled;
    final effectivePredictiveBackEnabled =
        _predictiveBackEnabled && !powerSaveModeEnabled;
    final effectiveMotionBlurEnabled =
        _motionBlurEnabled && !powerSaveModeEnabled;
    final effectiveLayerBlurEnabled =
        _layerBlurEnabled && !powerSaveModeEnabled;
    final effectiveLiquidGlassEnabled =
        _liquidGlassEnabled && !powerSaveModeEnabled;
    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('动画设置'),
              centerTitle: true,
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;
            final isWide = constraints.maxWidth > 600;
            final isCompact = constraints.maxWidth <= 600;
            final content = ListView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 24 : 16,
                widget.isEmbedded
                    ? (isDesktop ? 20 : 16)
                    : floatingGlassSettingsContentTopInset(context),
                isDesktop ? 24 : 16,
                isDesktop ? 32 : 16,
              ),
              children: [
                if (AppPlatform.isAndroid ||
                    widget.powerSaveModeOverride != null) ...[
                  Card(
                    elevation: 0,
                    color: powerSaveModeEnabled
                        ? colorScheme.primaryContainer.withValues(alpha: 0.72)
                        : colorScheme.surfaceContainerLow,
                    child: ListTile(
                      leading: Icon(
                        Icons.battery_saver_rounded,
                        color: powerSaveModeEnabled
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.primary,
                      ),
                      title: const Text('应用省电模式'),
                      subtitle: Text(
                        powerSaveModeEnabled
                            ? '已跟随 Android 系统自动开启：暂停装饰动画和玻璃特效，并降低传感器与后台探测频率。'
                            : '自动跟随 Android 系统省电模式；退出系统省电后会恢复你的动效偏好。',
                      ),
                      trailing: Text(
                        powerSaveModeEnabled ? '已开启' : '跟随系统',
                        style: TextStyle(
                          color: powerSaveModeEnabled
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isDesktop ? 20 : 16),
                ],
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '性能预设',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _buildPresetGrid(
                  isDesktop: isDesktop,
                  isWide: isWide,
                  isCompact: isCompact,
                ),
                SizedBox(height: isDesktop ? 28 : 24),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '核心特效开关',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (powerSaveModeEnabled) ...[
                        const SizedBox(height: 4),
                        Text(
                          '当前显示省电模式下的实际状态；退出后自动恢复原有偏好。懒加载优化继续启用以减少无效渲染。',
                          key: const ValueKey<String>(
                            'animation-settings-power-save-effective-note',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                GridView.count(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 3 : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: isDesktop ? 2.45 : 1.3,
                  children: [
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '启用页面动画',
                      subtitle: _effectSubtitle(
                        normal: '开启/关闭过渡动画',
                        preferredEnabled: _animationsEnabled,
                      ),
                      icon: Icons.animation,
                      value: effectiveAnimationsEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-page-animation-switch',
                      ),
                      onChanged: powerSaveModeEnabled
                          ? null
                          : (val) {
                              setState(() => _animationsEnabled = val);
                              _update(enabled: val);
                            },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '懒加载优化',
                      subtitle: powerSaveModeEnabled
                          ? '省电模式下继续启用，减少无效渲染'
                          : '动画进行中再渲染内容',
                      icon: Icons.hourglass_empty,
                      value: _lazyLoadEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-lazy-load-switch',
                      ),
                      onChanged: (val) {
                        setState(() => _lazyLoadEnabled = val);
                        _update(lazyLoad: val);
                      },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '屏幕圆角适配',
                      subtitle: _effectSubtitle(
                        normal: '动画过程中适配屏幕圆角',
                        preferredEnabled: _screenRadiusEnabled,
                      ),
                      icon: Icons.rounded_corner,
                      value: effectiveScreenRadiusEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-screen-radius-switch',
                      ),
                      onChanged: powerSaveModeEnabled
                          ? null
                          : (val) {
                              setState(() => _screenRadiusEnabled = val);
                              _update(screenRadius: val);
                            },
                    ),
                    if (!AppPlatform.isWeb)
                      _buildToggleCard(
                        isDesktop: isDesktop,
                        title: '预测性返回',
                        subtitle: _effectSubtitle(
                          normal: 'Android 14+ 返回手势',
                          preferredEnabled: _predictiveBackEnabled,
                        ),
                        icon: Icons.swipe_left,
                        value: effectivePredictiveBackEnabled,
                        switchKey: const ValueKey<String>(
                          'animation-settings-predictive-back-switch',
                        ),
                        onChanged: powerSaveModeEnabled
                            ? null
                            : (val) {
                                setState(() => _predictiveBackEnabled = val);
                                _update(predictiveBack: val);
                              },
                      ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '运动模糊',
                      subtitle: _effectSubtitle(
                        normal: '滑动动态模糊 (影响性能)',
                        preferredEnabled: _motionBlurEnabled,
                      ),
                      icon: Icons.blur_linear,
                      value: effectiveMotionBlurEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-motion-blur-switch',
                      ),
                      onChanged: powerSaveModeEnabled
                          ? null
                          : (val) {
                              setState(() => _motionBlurEnabled = val);
                              _update(motionBlur: val);
                            },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '层级模糊',
                      subtitle: _effectSubtitle(
                        normal: '背景页面模糊 (影响性能)',
                        preferredEnabled: _layerBlurEnabled,
                      ),
                      icon: Icons.blur_on,
                      value: effectiveLayerBlurEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-layer-blur-switch',
                      ),
                      onChanged: powerSaveModeEnabled
                          ? null
                          : (val) {
                              setState(() => _layerBlurEnabled = val);
                              _update(layerBlur: val);
                            },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: 'Liquid Glass',
                      cardKey: _glassKey,
                      subtitle: _effectSubtitle(
                        normal: '全应用玻璃材质、折射与半透明层次 (可选)',
                        preferredEnabled: _liquidGlassEnabled,
                      ),
                      icon: Icons.water_drop_rounded,
                      value: effectiveLiquidGlassEnabled,
                      switchKey: const ValueKey<String>(
                        'animation-settings-liquid-glass-switch',
                      ),
                      onChanged:
                          powerSaveModeEnabled || _liquidGlassMutationPending
                          ? null
                          : _setLiquidGlassEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: effectiveLiquidGlassEnabled ? 1 : 0.58,
                  child: Card(
                    color: _highlightTarget != null
                        ? colorScheme.primaryContainer
                        : null,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Liquid Glass 模式',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<LiquidGlassEffectMode>(
                              segments: const [
                                ButtonSegment(
                                  value: LiquidGlassEffectMode.standard,
                                  icon: Icon(Icons.speed_rounded),
                                  label: Text('标准'),
                                ),
                                ButtonSegment(
                                  value: LiquidGlassEffectMode.enhanced,
                                  icon: Icon(Icons.auto_awesome_rounded),
                                  label: Text('增强'),
                                ),
                              ],
                              selected: {_liquidGlassMode},
                              onSelectionChanged:
                                  !effectiveLiquidGlassEnabled ||
                                      _liquidGlassMutationPending
                                  ? null
                                  : (selection) =>
                                        _setLiquidGlassMode(selection.first),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _liquidGlassModeDescription,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (effectiveLiquidGlassEnabled) ...[
                            _buildTransparencyPreviewBox(
                              isDark: isDark,
                              colorScheme: colorScheme,
                              isEnabled: true,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_fix_high_rounded,
                                  size: 15,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '风格预设',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _buildStylePresetPills(
                              colorScheme: colorScheme,
                              isDark: isDark,
                              isEnabled: true,
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),

                            // --- 调整项 1: 底色遮蔽率 ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.format_color_fill_rounded,
                                      size: 17,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '底色遮蔽率',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '$_liquidGlassScrimCoverage%',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '控制玻璃底色浓度；数值越高越能遮挡壁纸杂色，保证文字对比与清晰度',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            LiquidGlassSlider(
                              key: const ValueKey<String>(
                                'animation-settings-liquid-glass-scrim-coverage',
                              ),
                              value: _liquidGlassScrimCoverage.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '$_liquidGlassScrimCoverage%',
                              onChanged: !effectiveLiquidGlassEnabled
                                  ? null
                                  : (val) => _updateLiquidGlassAdjustments(
                                      scrimCoverage: val.round(),
                                    ),
                            ),
                            _buildSliderQuickChips(
                              colorScheme: colorScheme,
                              isDark: isDark,
                              isEnabled: effectiveLiquidGlassEnabled,
                              items: [
                                (
                                  label: '30% 薄透',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    scrimCoverage: 30,
                                  ),
                                  isSelected: _liquidGlassScrimCoverage == 30,
                                ),
                                (
                                  label: '50% 柔和',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    scrimCoverage: 50,
                                  ),
                                  isSelected: _liquidGlassScrimCoverage == 50,
                                ),
                                (
                                  label: '70% 默认',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    scrimCoverage: 70,
                                  ),
                                  isSelected: _liquidGlassScrimCoverage == 70,
                                ),
                                (
                                  label: '90% 浓郁',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    scrimCoverage: 90,
                                  ),
                                  isSelected: _liquidGlassScrimCoverage == 90,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // --- 调整项 2: 透光度 ---
                            Row(
                              key: _transparencyKey,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.opacity_rounded,
                                      size: 17,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '透光度',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _getTransparencyLevelTag(
                                          _liquidGlassTransparency,
                                        ),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '$_liquidGlassTransparency%',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getTransparencyDescription(
                                _liquidGlassTransparency,
                              ),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            LiquidGlassSlider(
                              key: const ValueKey<String>(
                                'animation-settings-liquid-glass-transparency',
                              ),
                              value: _liquidGlassTransparency.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '$_liquidGlassTransparency%',
                              onChanged: !effectiveLiquidGlassEnabled
                                  ? null
                                  : (val) => _updateLiquidGlassAdjustments(
                                      transparency: val.round(),
                                    ),
                            ),
                            _buildSliderQuickChips(
                              colorScheme: colorScheme,
                              isDark: isDark,
                              isEnabled: effectiveLiquidGlassEnabled,
                              items: [
                                (
                                  label: '0% 纯色',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 0,
                                  ),
                                  isSelected: _liquidGlassTransparency == 0,
                                ),
                                (
                                  label: '35% 默认',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 35,
                                  ),
                                  isSelected: _liquidGlassTransparency == 35,
                                ),
                                (
                                  label: '50% 平衡',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 50,
                                  ),
                                  isSelected: _liquidGlassTransparency == 50,
                                ),
                                (
                                  label: '75% 轻透',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 75,
                                  ),
                                  isSelected: _liquidGlassTransparency == 75,
                                ),
                                (
                                  label: '100% 全透',
                                  onTap: () => _updateLiquidGlassAdjustments(
                                    transparency: 100,
                                  ),
                                  isSelected: _liquidGlassTransparency == 100,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // --- 调整项 3: 模糊程度 ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.blur_on_rounded,
                                      size: 18,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '模糊程度',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${_liquidGlassBlur.round()}px',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '控制卡片背后的高斯磨砂柔化半径；数值越大磨砂越柔和朦胧',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            LiquidGlassSlider(
                              key: const ValueKey<String>(
                                'animation-settings-liquid-glass-blur',
                              ),
                              value: _liquidGlassBlur,
                              min: 0,
                              max: 30,
                              divisions: 30,
                              label: '${_liquidGlassBlur.round()}px',
                              onChanged: !effectiveLiquidGlassEnabled
                                  ? null
                                  : (val) => _updateLiquidGlassAdjustments(
                                      blur: val,
                                    ),
                            ),
                            _buildSliderQuickChips(
                              colorScheme: colorScheme,
                              isDark: isDark,
                              isEnabled: effectiveLiquidGlassEnabled,
                              items: [
                                (
                                  label: '0px 无模糊',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 0),
                                  isSelected: _liquidGlassBlur == 0,
                                ),
                                (
                                  label: '3px 默认',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 3),
                                  isSelected: _liquidGlassBlur == 3,
                                ),
                                (
                                  label: '8px 轻度',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 8),
                                  isSelected: _liquidGlassBlur == 8,
                                ),
                                (
                                  label: '16px 标准',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 16),
                                  isSelected: _liquidGlassBlur == 16,
                                ),
                                (
                                  label: '24px 深度磨砂',
                                  onTap: () =>
                                      _updateLiquidGlassAdjustments(blur: 24),
                                  isSelected: _liquidGlassBlur == 24,
                                ),
                              ],
                            ),

                            // --- 实时应用与保存操作区 ---
                            ValueListenableBuilder<bool>(
                              valueListenable: LiquidGlassEffectService
                                  .hasUnsavedChangesListenable,
                              builder: (context, hasUnsaved, _) {
                                if (!effectiveLiquidGlassEnabled) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  margin: const EdgeInsets.only(top: 14),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: hasUnsaved
                                        ? colorScheme.primaryContainer
                                              .withValues(alpha: 0.28)
                                        : colorScheme.surfaceContainerHighest
                                              .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: hasUnsaved
                                          ? colorScheme.primary.withValues(
                                              alpha: 0.3,
                                            )
                                          : colorScheme.outlineVariant
                                                .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            hasUnsaved
                                                ? Icons.auto_awesome_rounded
                                                : Icons
                                                      .check_circle_outline_rounded,
                                            size: 18,
                                            color: hasUnsaved
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              hasUnsaved
                                                  ? '效果已在全应用各界面实时生效'
                                                  : '当前玻璃效果已保存',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        hasUnsaved
                                            ? '可在主页与其他界面查看实际壁纸和卡片效果，满意后再保存；不满意可随时还原。'
                                            : '微调滑块或预设可实时应用预览，满意后可点击保存。',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton.icon(
                                            key: const ValueKey(
                                              'animation-settings-liquid-glass-reset-button',
                                            ),
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              '恢复默认',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            onPressed:
                                                !effectiveLiquidGlassEnabled
                                                ? null
                                                : () {
                                                    LiquidGlassEffectService.resetToDefaults();
                                                    final config =
                                                        LiquidGlassEffectService
                                                            .preferredConfiguration;
                                                    setState(() {
                                                      _liquidGlassScrimCoverage =
                                                          config
                                                              .scrimCoveragePercent;
                                                      _liquidGlassTransparency =
                                                          config
                                                              .transparencyPercent;
                                                      _liquidGlassBlur =
                                                          config.blurSigma;
                                                    });
                                                  },
                                          ),
                                          const SizedBox(width: 6),
                                          OutlinedButton.icon(
                                            key: const ValueKey(
                                              'animation-settings-liquid-glass-float-button',
                                            ),
                                            icon: const Icon(
                                              Icons.open_in_browser_rounded,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              '悬浮调节',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            onPressed:
                                                !effectiveLiquidGlassEnabled
                                                ? null
                                                : () {
                                                    LiquidGlassEffectService.startLivePreview(
                                                      expand: true,
                                                    );
                                                    Navigator.of(context)
                                                        .maybePop();
                                                  },
                                          ),
                                          if (hasUnsaved) ...[
                                            const SizedBox(width: 6),
                                            OutlinedButton.icon(
                                              key: const ValueKey(
                                                'animation-settings-liquid-glass-revert-button',
                                              ),
                                              icon: const Icon(
                                                Icons.undo_rounded,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                '还原',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              onPressed:
                                                  !effectiveLiquidGlassEnabled
                                                  ? null
                                                  : () {
                                                      LiquidGlassEffectService.revertAdjustments();
                                                      final config =
                                                          LiquidGlassEffectService
                                                              .persistedConfiguration;
                                                      setState(() {
                                                        _liquidGlassScrimCoverage =
                                                            config
                                                                .scrimCoveragePercent;
                                                        _liquidGlassTransparency =
                                                            config
                                                                .transparencyPercent;
                                                        _liquidGlassBlur =
                                                            config.blurSigma;
                                                      });
                                                      AppSnackBars.showSnackBar(
                                                        context,
                                                        const SnackBar(
                                                          content: Text(
                                                            '已还原上次保存的玻璃设置',
                                                          ),
                                                        ),
                                                      );
                                                    },
                                            ),
                                            const SizedBox(width: 8),
                                            FilledButton.icon(
                                              key: const ValueKey(
                                                'animation-settings-liquid-glass-save-button',
                                              ),
                                              icon: const Icon(
                                                Icons.check_rounded,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                '保存效果',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              onPressed:
                                                  !effectiveLiquidGlassEnabled
                                                  ? null
                                                  : () =>
                                                        _saveLiquidGlassAdjustments(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                          if (!effectiveLiquidGlassEnabled) ...[
                            const SizedBox(height: 6),
                            Text(
                              powerSaveModeEnabled && _liquidGlassEnabled
                                  ? '省电模式下已暂停；退出后恢复${_liquidGlassMode == LiquidGlassEffectMode.standard ? '标准' : '增强'}模式'
                                  : '开启 Liquid Glass 后可切换模式',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 8.0,
                    bottom: 8.0,
                    top: 32.0,
                  ),
                  child: Text(
                    '参数微调',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '动画时长',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${_animationDuration}ms',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LiquidGlassSlider(
                              value: _animationDuration.toDouble(),
                              min: 150,
                              max: 600,
                              divisions: 9,
                              label: '${_animationDuration}ms',
                              onChanged: (val) {
                                setState(
                                  () => _animationDuration = val.round(),
                                );
                                _update(duration: val.round());
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '快',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '慢',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '动画速度预设',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildSpeedPresetChip(
                                  preset: AnimationSpeedPreset.elegant,
                                  title: '优雅',
                                ),
                                _buildSpeedPresetChip(
                                  preset: AnimationSpeedPreset.balanced,
                                  title: '均衡',
                                ),
                                _buildSpeedPresetChip(
                                  preset: AnimationSpeedPreset.fast,
                                  title: '快速',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '层级深度',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '$_pageLayerDepth%',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '控制背景页缩小、压暗和层级模糊强度',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LiquidGlassSlider(
                              value: _pageLayerDepth.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 10,
                              label: '$_pageLayerDepth%',
                              onChanged: (val) {
                                final next = val.round();
                                setState(() => _pageLayerDepth = next);
                                _update(pageLayerDepth: next);
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '轻',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '强',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '元素展开内容显现',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '$_containerContentStart%',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '控制从卡片、按钮展开页面时内容出现的早晚',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LiquidGlassSlider(
                              value: _containerContentStart.toDouble(),
                              min: 0,
                              max: 60,
                              divisions: 12,
                              label: '$_containerContentStart%',
                              onChanged: (val) {
                                final next = val.round();
                                setState(() => _containerContentStart = next);
                                _update(containerContentStart: next);
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '早',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '晚',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isDesktop ? 24 : 40),
              ],
            );

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 1440 : constraints.maxWidth,
                ),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSpeedPresetChip({
    required AnimationSpeedPreset preset,
    required String title,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _speedPreset == preset;
    return ChoiceChip(
      label: Text('$title ${preset.duration}ms'),
      selected: selected,
      showCheckmark: false,
      onSelected: (value) {
        if (value) _applySpeedPreset(preset);
      },
      selectedColor: colorScheme.primaryContainer,
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(
        color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        width: selected ? 1.5 : 1,
      ),
      labelStyle: TextStyle(
        color: selected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _buildPresetGrid({
    required bool isDesktop,
    required bool isWide,
    required bool isCompact,
  }) {
    return GridView.count(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // 三种策略始终并排，便于快速对比和切换；窄屏使用更紧凑的卡片
      // 排版，避免把性能选项推到很深的位置。
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: isDesktop ? 2.35 : (isWide ? 1.45 : 0.78),
      children: [
        _buildPresetCard(
          compact: isCompact,
          preset: AnimationPreset.performance,
          title: '极致流畅',
          subtitle: '快速动画，优先稳定帧率，关闭液态玻璃',
          icon: Icons.speed_rounded,
        ),
        _buildPresetCard(
          compact: isCompact,
          preset: AnimationPreset.balanced,
          title: '均衡模式',
          subtitle: '均衡动画，保留主要过渡，液态玻璃标准档',
          icon: Icons.tune_rounded,
        ),
        _buildPresetCard(
          compact: isCompact,
          preset: AnimationPreset.expressive,
          title: '完整动效',
          subtitle: '优雅动画，开启模糊与液态玻璃增强档',
          icon: Icons.auto_awesome_rounded,
        ),
      ],
    );
  }

  Widget _buildPresetCard({
    required bool compact,
    required AnimationPreset preset,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _preset == preset;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _applyPreset(preset),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: selected ? 2 : 0,
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 14,
            vertical: compact ? 8 : 10,
          ),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 22,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 22,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          if (selected)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 17,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      icon,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        color: colorScheme.primary,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required bool isDesktop,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool>? onChanged,
    Key? switchKey,
    Key? cardKey,
  }) {
    return SettingsToggleCard(
      key: cardKey,
      isDesktop: isDesktop,
      title: title,
      subtitle: subtitle,
      icon: icon,
      value: value,
      onChanged: onChanged,
      switchKey: switchKey,
      mobileUseSpacer: true,
    );
  }

  String _effectSubtitle({
    required String normal,
    required bool preferredEnabled,
  }) {
    if (!_powerSaveModeEnabled) return normal;
    return preferredEnabled ? '省电模式下已暂停，退出后自动恢复' : '已关闭，退出省电后保持关闭';
  }

  String _getTransparencyLevelTag(int value) {
    if (value == 0) return '纯色遮蔽';
    if (value <= 35) return '浓郁磨砂';
    if (value <= 65) return '经典平衡';
    if (value <= 90) return '轻透薄雾';
    return '全透水晶';
  }

  String _getTransparencyDescription(int value) {
    if (value == 0) {
      return '底色完全不透明，遮蔽背景内容，文字与图标对比度最高';
    }
    if (value <= 35) {
      return '深色调浓郁磨砂，仅隐约透出背景轮廓与主色';
    }
    if (value <= 65) {
      return '原版经典毛玻璃质感，透光度与界面可读性达到最佳平衡';
    }
    if (value <= 90) {
      return '轻盈通透的薄雾玻璃，更明显地透出壁纸与底层丰富细节';
    }
    return '接近纯粹透明的水晶质感，底层色彩完全透出';
  }

  Widget _buildTransparencyPreviewBox({
    required bool isDark,
    required ColorScheme colorScheme,
    required bool isEnabled,
  }) {
    final config = LiquidGlassEffectConfiguration(
      enabled: isEnabled,
      mode: _liquidGlassMode,
      transparencyPercent: _liquidGlassTransparency,
      scrimCoveragePercent: _liquidGlassScrimCoverage,
      blurSigma: _liquidGlassBlur,
    );
    final fillOpacity = isEnabled
        ? liquidGlassBackerOpacity(isDark ? 0.65 : 0.78, config)
        : (isDark ? 0.70 : 0.85);
    final blurSigma = isEnabled ? _liquidGlassBlur : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      height: 104,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [
                        Color(0xFF1E2640),
                        Color(0xFF3B1E48),
                        Color(0xFF1E3830),
                      ]
                    : const [
                        Color(0xFFE0E7FF),
                        Color(0xFFFCE7F3),
                        Color(0xFFDCFCE7),
                      ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            top: 14,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFFF5252), Color(0xFFFF7A00)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.4),
                    blurRadius: 16,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 36,
            bottom: 8,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF2979FF), Color(0xFF00E5FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2979FF).withValues(alpha: 0.4),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            bottom: 12,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.08,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '底层色彩与内容',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.black : Colors.white).withValues(
                        alpha: fillOpacity,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: isDark ? 0.18 : 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '毛玻璃卡片实时透光',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isEnabled
                                    ? '遮蔽 $_liquidGlassScrimCoverage% · 透光 $_liquidGlassTransparency% · 模糊 ${_liquidGlassBlur.round()}px'
                                    : 'Liquid Glass 未启用',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$_liquidGlassTransparency%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStylePresetPills({
    required ColorScheme colorScheme,
    required bool isDark,
    required bool isEnabled,
  }) {
    final presets = [
      (name: '舒适清透', desc: '默认', scrim: 70, trans: 35, blur: 3.0),
      (name: '轻透水晶', desc: '通透', scrim: 45, trans: 75, blur: 20.0),
      (name: '深层磨砂', desc: '质感', scrim: 75, trans: 40, blur: 25.0),
      (name: '高对比度', desc: '清晰', scrim: 90, trans: 20, blur: 12.0),
      (name: '微光微磨', desc: '轻柔', scrim: 55, trans: 65, blur: 8.0),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: presets.map((item) {
          final isSelected =
              _liquidGlassScrimCoverage == item.scrim &&
              _liquidGlassTransparency == item.trans &&
              (_liquidGlassBlur - item.blur).abs() < 0.5;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: !isEnabled
                      ? null
                      : () {
                          _updateLiquidGlassAdjustments(
                            scrimCoverage: item.scrim,
                            transparency: item.trans,
                            blur: item.blur,
                          );
                        },
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(
                              alpha: isDark ? 0.25 : 0.12,
                            )
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(
                                alpha: 0.25,
                              ),
                        width: isSelected ? 1.4 : 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          item.desc,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSliderQuickChips({
    required ColorScheme colorScheme,
    required bool isDark,
    required bool isEnabled,
    required List<({String label, VoidCallback onTap, bool isSelected})> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: items.map((item) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled ? item.onTap : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: item.isSelected
                          ? colorScheme.primary.withValues(
                              alpha: isDark ? 0.24 : 0.12,
                            )
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.03)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: item.isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.2),
                        width: item.isSelected ? 1.2 : 0.8,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: item.isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: item.isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
