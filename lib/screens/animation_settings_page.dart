import 'package:flutter/material.dart';
import '../services/animation_config_service.dart';
import '../services/liquid_glass_effect_service.dart';
import '../utils/app_platform.dart';
import '../utils/page_transitions.dart';
import '../widgets/floating_glass_control.dart';

class AnimationSettingsPage extends StatefulWidget {
  final bool isEmbedded;

  const AnimationSettingsPage({super.key, this.isEmbedded = false});

  @override
  State<AnimationSettingsPage> createState() => _AnimationSettingsPageState();
}

class _AnimationSettingsPageState extends State<AnimationSettingsPage> {
  bool _animationsEnabled = true;
  bool _motionBlurEnabled = false;
  bool _layerBlurEnabled = false;
  bool _liquidGlassEnabled = false;
  LiquidGlassEffectMode _liquidGlassMode = LiquidGlassEffectMode.standard;
  bool _liquidGlassMutationPending = false;
  bool _lazyLoadEnabled = true;
  bool _screenRadiusEnabled = true;
  bool _predictiveBackEnabled = true;
  int _animationDuration = AnimationSpeedPreset.elegant.duration;
  int _pageLayerDepth = 18;
  int _containerContentStart = 12;
  AnimationPreset? _preset = AnimationPreset.balanced;
  AnimationSpeedPreset? _speedPreset = AnimationSpeedPreset.elegant;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Liquid Glass 模式切换失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _liquidGlassMutationPending = false);
      }
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
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 24 : 16,
                widget.isEmbedded
                    ? (isDesktop ? 20 : 16)
                    : floatingGlassSettingsContentTopInset(
                        context,
                        extra: isDesktop ? 20 : 16,
                      ),
                isDesktop ? 24 : 16,
                isDesktop ? 32 : 16,
              ),
              children: [
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
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text('核心特效开关',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant)),
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
                      subtitle: '开启/关闭过渡动画',
                      icon: Icons.animation,
                      value: _animationsEnabled,
                      onChanged: (val) {
                        setState(() => _animationsEnabled = val);
                        _update(enabled: val);
                      },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '懒加载优化',
                      subtitle: '动画进行中再渲染内容',
                      icon: Icons.hourglass_empty,
                      value: _lazyLoadEnabled,
                      onChanged: (val) {
                        setState(() => _lazyLoadEnabled = val);
                        _update(lazyLoad: val);
                      },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '屏幕圆角适配',
                      subtitle: '动画过程中适配屏幕圆角',
                      icon: Icons.rounded_corner,
                      value: _screenRadiusEnabled,
                      onChanged: (val) {
                        setState(() => _screenRadiusEnabled = val);
                        _update(screenRadius: val);
                      },
                    ),
                    if (!AppPlatform.isWeb)
                      _buildToggleCard(
                        isDesktop: isDesktop,
                        title: '预测性返回',
                        subtitle: 'Android 14+ 返回手势',
                        icon: Icons.swipe_left,
                        value: _predictiveBackEnabled,
                        onChanged: (val) {
                          setState(() => _predictiveBackEnabled = val);
                          _update(predictiveBack: val);
                        },
                      ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '运动模糊',
                      subtitle: '滑动动态模糊 (影响性能)',
                      icon: Icons.blur_linear,
                      value: _motionBlurEnabled,
                      onChanged: (val) {
                        setState(() => _motionBlurEnabled = val);
                        _update(motionBlur: val);
                      },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: '层级模糊',
                      subtitle: '背景页面模糊 (影响性能)',
                      icon: Icons.blur_on,
                      value: _layerBlurEnabled,
                      onChanged: (val) {
                        setState(() => _layerBlurEnabled = val);
                        _update(layerBlur: val);
                      },
                    ),
                    _buildToggleCard(
                      isDesktop: isDesktop,
                      title: 'Liquid Glass',
                      subtitle: '全应用玻璃材质、折射与半透明层次 (可选)',
                      icon: Icons.water_drop_rounded,
                      value: _liquidGlassEnabled,
                      onChanged: _liquidGlassMutationPending
                          ? null
                          : _setLiquidGlassEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _liquidGlassEnabled ? 1 : 0.58,
                  child: Card(
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
                              onSelectionChanged: !_liquidGlassEnabled ||
                                      _liquidGlassMutationPending
                                  ? null
                                  : (selection) =>
                                      _setLiquidGlassMode(selection.first),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _liquidGlassMode == LiquidGlassEffectMode.standard
                                ? '高可读性和低功耗；滚动卡片使用轻量玻璃材质，重点表面保留折射。'
                                : '更强折射、高光和色散；固定重点表面使用高画质玻璃，滚动卡片启用实时玻璃。',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (!_liquidGlassEnabled) ...[
                            const SizedBox(height: 6),
                            Text(
                              '开启 Liquid Glass 后可切换模式',
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
                  padding:
                      const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 32.0),
                  child: Text('参数微调',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant)),
                ),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('动画时长',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                Text('${_animationDuration}ms',
                                    style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: _animationDuration.toDouble(),
                              min: 150,
                              max: 600,
                              divisions: 9,
                              label: '${_animationDuration}ms',
                              onChanged: (val) {
                                setState(
                                    () => _animationDuration = val.round());
                                _update(duration: val.round());
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('快',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant)),
                                Text('慢',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('动画速度预设',
                                style: TextStyle(fontWeight: FontWeight.w600)),
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
                            horizontal: 16, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('层级深度',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                Text('$_pageLayerDepth%',
                                    style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('控制背景页缩小、压暗和层级模糊强度',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            Slider(
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
                                Text('轻',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant)),
                                Text('强',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('元素展开内容显现',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                Text('$_containerContentStart%',
                                    style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('控制从卡片、按钮展开页面时内容出现的早晚',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            Slider(
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
                                Text('早',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant)),
                                Text('晚',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant)),
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
                              child: Icon(Icons.check_circle_rounded,
                                  size: 17, color: colorScheme.primary),
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
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(icon,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle_rounded,
                          color: colorScheme.primary),
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
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = value;
    final iconWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInBack,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return ScaleTransition(
          scale: animation,
          child: RotationTransition(
            turns: Tween<double>(begin: -0.1, end: 0.0).animate(animation),
            child: child,
          ),
        );
      },
      child: Icon(
        icon,
        key: ValueKey<bool>(isSelected),
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: isDesktop ? 28 : 32,
      ),
    );
    final switchWidget = SizedBox(
      height: 24,
      child: FittedBox(
        fit: BoxFit.fill,
        child: LiquidGlassSwitch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colorScheme.primary,
        ),
      ),
    );
    final titleWidget = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: isSelected
            ? colorScheme.primary
            : theme.textTheme.bodyMedium?.color,
        fontFamily: theme.textTheme.bodyMedium?.fontFamily,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: Text(title),
    );
    final subtitleWidget = Text(
      subtitle,
      maxLines: isDesktop ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
    );

    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.all(isDesktop ? 16 : 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.1)
              : (theme.brightness == Brightness.dark
                  ? Colors.grey.shade900
                  : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: isDesktop
            ? Row(
                children: [
                  iconWidget,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 3),
                        subtitleWidget,
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  switchWidget,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [iconWidget, switchWidget],
                  ),
                  const Spacer(),
                  titleWidget,
                  const SizedBox(height: 2),
                  subtitleWidget,
                ],
              ),
      ),
    );
  }
}
