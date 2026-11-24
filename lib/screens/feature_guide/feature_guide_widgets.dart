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
    _load();
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
                '全局磨砂质感与折射视觉，可在"动效设置"中调整模式',
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
