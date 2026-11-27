part of '../feature_guide_screen.dart';

class AssetVideoPlayer extends StatefulWidget {
  final String assetPath;

  const AssetVideoPlayer({super.key, required this.assetPath});

  @override
  State<AssetVideoPlayer> createState() => _AssetVideoPlayerState();
}

class _AssetVideoPlayerState extends State<AssetVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.assetPath)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _initialized = true;
          });
          _controller.setLooping(true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized) {
      return AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      );
    } else {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
  }
}

/// 引导页外观选项区：深色模式 + 液态玻璃开关。
///
/// 独立成组件便于复用与测试；选择立即持久化。
class GuideAppearanceOptions extends StatefulWidget {
  const GuideAppearanceOptions({super.key});

  @override
  State<GuideAppearanceOptions> createState() => _GuideAppearanceOptionsState();
}

class _GuideAppearanceOptionsState extends State<GuideAppearanceOptions> {
  String _themeMode = 'system';
  bool _liquidGlassEnabled = false;

  @override
  void initState() {
    super.initState();
    LiquidGlassEffectService.configurationListenable.addListener(
      _syncLiquidGlassFromService,
    );
    _load();
  }

  @override
  void dispose() {
    LiquidGlassEffectService.configurationListenable.removeListener(
      _syncLiquidGlassFromService,
    );
    super.dispose();
  }

  void _syncLiquidGlassFromService() {
    if (!mounted) return;
    final nextEnabled = LiquidGlassEffectService.preferredConfiguration.enabled;
    if (nextEnabled != _liquidGlassEnabled) {
      setState(() => _liquidGlassEnabled = nextEnabled);
    }
  }

  Future<void> _load() async {
    final theme = await StorageService.getThemeMode();
    final glass = await LiquidGlassEffectService.loadEnabled();
    if (!mounted) return;
    setState(() {
      if (const {'system', 'light', 'dark'}.contains(theme)) {
        _themeMode = theme;
      }
      _liquidGlassEnabled = glass;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        OptionalLiquidGlassCard(
          margin: EdgeInsets.zero,
          borderRadius: 12,
          highContrast: true,
          fallbackDecoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('深色模式/主题', style: TextStyle(fontSize: 14)),
              trailing: DropdownButton<String>(
                value: _themeMode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                  DropdownMenuItem(value: 'light', child: Text('浅色')),
                  DropdownMenuItem(value: 'dark', child: Text('深色')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _themeMode = val);
                    StorageService.saveAppSetting(
                      StorageService.keyThemeMode,
                      val,
                    );
                    StorageService.themeNotifier.value = val;
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OptionalLiquidGlassCard(
          key: const ValueKey('guide-liquid-glass-card'),
          margin: EdgeInsets.zero,
          borderRadius: 12,
          highContrast: true,
          tint: _liquidGlassEnabled
              ? scheme.primary.withValues(alpha: 0.16)
              : null,
          fallbackDecoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: LiquidGlassSwitchListTile(
              key: const ValueKey('guide-liquid-glass-switch'),
              value: _liquidGlassEnabled,
              secondary: const Icon(Icons.blur_on_rounded),
              title: const Text('液态玻璃效果', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '本版本默认开启标准液态玻璃，可在此切换，也可在"动效设置"中微调',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              onChanged: (val) {
                setState(() => _liquidGlassEnabled = val);
                LiquidGlassEffectService.setEnabled(val);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 版本更新日志页内的液态玻璃默认开启说明与快捷切换卡片。
class GuideLiquidGlassDefaultCard extends StatelessWidget {
  const GuideLiquidGlassDefaultCard({super.key});

  String _selectionFor(LiquidGlassEffectConfiguration preferred) {
    if (!preferred.enabled) return 'off';
    if (!AppPlatform.isWindows &&
        preferred.mode == LiquidGlassEffectMode.enhanced) {
      return 'enhanced';
    }
    return 'standard';
  }

  Future<void> _applySelection(String value) async {
    switch (value) {
      case 'off':
        await LiquidGlassEffectService.setEnabled(false);
        return;
      case 'enhanced':
        await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.enhanced);
        await LiquidGlassEffectService.setEnabled(true);
        return;
      case 'standard':
      default:
        await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
        await LiquidGlassEffectService.setEnabled(true);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, _, _) {
        final preferred = LiquidGlassEffectService.preferredConfiguration;
        final selection = _selectionFor(preferred);
        final isEnhanced = selection == 'enhanced';
        final isEnabled = selection != 'off';
        final title = isEnhanced
            ? '已保留「增强液态玻璃」'
            : isEnabled
            ? '已默认启用「标准液态玻璃」'
            : '液态玻璃已关闭';
        final subtitle = isEnhanced
            ? '本版本流畅度大幅提升，已为你保留原有的增强液态玻璃设置，也可在此直接切换。'
            : isEnabled
            ? '本版本流畅度大幅提升，升级后已为你默认开启标准液态玻璃，可直接在下方切换。'
            : '本版本升级默认启用标准液态玻璃；你已将其关闭，随时可在此重新开启。';

        return OptionalLiquidGlassCard(
          key: const ValueKey('guide-changelog-liquid-glass-card'),
          width: double.infinity,
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(16),
          borderRadius: 16,
          highContrast: true,
          tint: isEnabled ? scheme.primary.withValues(alpha: 0.14) : null,
          fallbackDecoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled
                  ? scheme.primary.withValues(alpha: 0.3)
                  : scheme.outlineVariant,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? scheme.primary.withValues(alpha: 0.14)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.blur_on_rounded,
                        size: 20,
                        color: isEnabled
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    key: const ValueKey('guide-changelog-liquid-glass-toggle'),
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment<String>(
                        value: 'off',
                        label: Text(
                          '关闭',
                          key: ValueKey('guide-changelog-liquid-glass-off'),
                        ),
                      ),
                      const ButtonSegment<String>(
                        value: 'standard',
                        label: Text(
                          '标准',
                          key: ValueKey(
                            'guide-changelog-liquid-glass-standard',
                          ),
                        ),
                      ),
                      if (!AppPlatform.isWindows)
                        const ButtonSegment<String>(
                          value: 'enhanced',
                          label: Text(
                            '增强',
                            key: ValueKey(
                              'guide-changelog-liquid-glass-enhanced',
                            ),
                          ),
                        ),
                    ],
                    selected: <String>{selection},
                    onSelectionChanged: (values) {
                      if (values.isEmpty) return;
                      unawaited(_applySelection(values.first));
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
