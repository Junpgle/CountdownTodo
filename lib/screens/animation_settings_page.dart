import 'package:flutter/material.dart';
import '../services/animation_config_service.dart';
import '../utils/page_transitions.dart';

class AnimationSettingsPage extends StatefulWidget {
  const AnimationSettingsPage({super.key});

  @override
  State<AnimationSettingsPage> createState() => _AnimationSettingsPageState();
}

class _AnimationSettingsPageState extends State<AnimationSettingsPage> {
  bool _animationsEnabled = true;
  bool _motionBlurEnabled = false;
  bool _layerBlurEnabled = false;
  bool _lazyLoadEnabled = true;
  bool _screenRadiusEnabled = true;
  bool _predictiveBackEnabled = true;
  int _animationDuration = 500;

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
    ]);
    setState(() {
      _animationsEnabled = results[0] as bool;
      _motionBlurEnabled = results[1] as bool;
      _layerBlurEnabled = results[2] as bool;
      _lazyLoadEnabled = results[3] as bool;
      _screenRadiusEnabled = results[4] as bool;
      _predictiveBackEnabled = results[5] as bool;
      _animationDuration = results[6] as int;
    });
  }

  Future<void> _update({
    bool? enabled,
    bool? motionBlur,
    bool? layerBlur,
    bool? lazyLoad,
    bool? screenRadius,
    bool? predictiveBack,
    int? duration,
  }) async {
    if (enabled != null)
      await AnimationConfigService.setAnimationsEnabled(enabled);
    if (motionBlur != null)
      await AnimationConfigService.setMotionBlurEnabled(motionBlur);
    if (layerBlur != null)
      await AnimationConfigService.setLayerBlurEnabled(layerBlur);
    if (lazyLoad != null)
      await AnimationConfigService.setLazyLoadEnabled(lazyLoad);
    if (screenRadius != null)
      await AnimationConfigService.setScreenRadiusEnabled(screenRadius);
    if (predictiveBack != null)
      await AnimationConfigService.setPredictiveBackEnabled(predictiveBack);
    if (duration != null)
      await AnimationConfigService.setAnimationDuration(duration);
    await PageTransitions.init();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('动画设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('启用页面动画',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('开启/关闭所有页面过渡动画'),
                  value: _animationsEnabled,
                  activeColor: colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _animationsEnabled = val);
                    _update(enabled: val);
                  },
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('懒加载优化',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('动画进行中再渲染页面内容，提升流畅度'),
                  value: _lazyLoadEnabled,
                  activeColor: colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _lazyLoadEnabled = val);
                    _update(lazyLoad: val);
                  },
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('屏幕圆角适配',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('动画过程中适配设备屏幕圆角'),
                  value: _screenRadiusEnabled,
                  activeColor: colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _screenRadiusEnabled = val);
                    _update(screenRadius: val);
                  },
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('预测性返回动画',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('支持 Android 14+ 预测性返回手势动画'),
                  value: _predictiveBackEnabled,
                  activeColor: colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _predictiveBackEnabled = val);
                    _update(predictiveBack: val);
                  },
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('运动模糊',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('页面滑动时添加动态模糊效果（可能影响性能）'),
                  value: _motionBlurEnabled,
                  activeColor: colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _motionBlurEnabled = val);
                    _update(motionBlur: val);
                  },
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('层级模糊',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('前景页面清晰，背景页面模糊（可能影响性能）'),
                  value: _layerBlurEnabled,
                  activeColor: colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _layerBlurEnabled = val);
                    _update(layerBlur: val);
                  },
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('动画时长',
                              style: TextStyle(fontWeight: FontWeight.w600)),
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
                          setState(() => _animationDuration = val.round());
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
