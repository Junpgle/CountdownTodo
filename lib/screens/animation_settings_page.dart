import 'package:flutter/material.dart';
import '../services/animation_config_service.dart';
import '../utils/app_platform.dart';
import '../utils/page_transitions.dart';

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
  bool _lazyLoadEnabled = true;
  bool _screenRadiusEnabled = true;
  bool _predictiveBackEnabled = true;
  int _animationDuration = 500;
  int _pageLayerDepth = 60;
  int _containerContentStart = 28;

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
    ]);
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
    int? pageLayerDepth,
    int? containerContentStart,
  }) async {
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
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('动画设置'),
              centerTitle: true,
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
            child: Text('核心特效开关',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _buildToggleCard(
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
                title: '层级模糊',
                subtitle: '背景页面模糊 (影响性能)',
                icon: Icons.blur_on,
                value: _layerBlurEnabled,
                onChanged: (val) {
                  setState(() => _layerBlurEnabled = val);
                  _update(layerBlur: val);
                },
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 32.0),
            child: Text('参数微调',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          Card(
            elevation: 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('层级深度',
                              style: TextStyle(fontWeight: FontWeight.w600)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('元素展开内容显现',
                              style: TextStyle(fontWeight: FontWeight.w600)),
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
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = value;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInBack,
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: RotationTransition(
                        turns: Tween<double>(begin: -0.1, end: 0.0)
                            .animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Icon(
                    icon,
                    key: ValueKey<bool>(isSelected),
                    color: isSelected ? colorScheme.primary : Colors.grey,
                    size: 32,
                  ),
                ),
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: Switch(
                      value: value,
                      onChanged: onChanged,
                      activeColor: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            AnimatedDefaultTextStyle(
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
            ),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
