import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'liquid_glass_effect_service.dart';

enum AnimationPreset { performance, balanced, expressive }

class AnimationConfigService {
  static const String _keyPreset = 'animation_preset';
  static const String _keyEnableAnimations = 'enable_animations';
  static const String _keyEnableMotionBlur = 'enable_motion_blur';
  static const String _keyEnableLayerBlur = 'enable_layer_blur';
  static const String _keyEnableLazyLoad = 'enable_lazy_load';
  static const String _keyEnableScreenRadius = 'enable_screen_radius';
  static const String _keyEnablePredictiveBack = 'enable_predictive_back';
  static const String _keyAnimationDuration = 'animation_duration';
  static const String _keyPageLayerDepth = 'page_layer_depth';
  static const String _keyContainerContentStart = 'container_content_start';

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<AnimationPreset?> getPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyPreset);
    for (final preset in AnimationPreset.values) {
      if (preset.name == value) return preset;
    }
    return null;
  }

  static Future<bool> isAnimationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableAnimations) ?? true;
  }

  static Future<bool> isMotionBlurEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableMotionBlur) ?? false;
  }

  static Future<bool> isLayerBlurEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableLayerBlur) ?? false;
  }

  static Future<bool> isLazyLoadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableLazyLoad) ?? true;
  }

  static Future<bool> isScreenRadiusEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableScreenRadius) ?? true;
  }

  static Future<bool> isPredictiveBackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnablePredictiveBack) ?? true;
  }

  static Future<int> getAnimationDuration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyAnimationDuration) ?? (_isAndroid ? 220 : 500);
  }

  static Future<int> getPageLayerDepth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPageLayerDepth) ?? (_isAndroid ? 18 : 60);
  }

  static Future<int> getContainerContentStart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyContainerContentStart) ?? (_isAndroid ? 12 : 28);
  }

  /// Apply a complete visual/performance profile in one user action.
  ///
  /// The performance profile keeps useful motion but removes the expensive
  /// blur layers that most often block the raster thread on Android phones.
  static Future<void> setPreset(AnimationPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    late final Map<String, Object> values;
    switch (preset) {
      case AnimationPreset.performance:
        values = {
          _keyEnableAnimations: true,
          _keyEnableMotionBlur: false,
          _keyEnableLayerBlur: false,
          _keyEnableLazyLoad: true,
          _keyEnableScreenRadius: true,
          _keyEnablePredictiveBack: true,
          _keyAnimationDuration: 220,
          _keyPageLayerDepth: 18,
          _keyContainerContentStart: 12,
        };
      case AnimationPreset.balanced:
        values = {
          _keyEnableAnimations: true,
          _keyEnableMotionBlur: false,
          _keyEnableLayerBlur: false,
          _keyEnableLazyLoad: true,
          _keyEnableScreenRadius: true,
          _keyEnablePredictiveBack: true,
          _keyAnimationDuration: 320,
          _keyPageLayerDepth: 36,
          _keyContainerContentStart: 18,
        };
      case AnimationPreset.expressive:
        values = {
          _keyEnableAnimations: true,
          _keyEnableMotionBlur: true,
          _keyEnableLayerBlur: true,
          _keyEnableLazyLoad: false,
          _keyEnableScreenRadius: true,
          _keyEnablePredictiveBack: true,
          _keyAnimationDuration: 500,
          _keyPageLayerDepth: 60,
          _keyContainerContentStart: 28,
        };
    }

    await prefs.setString(_keyPreset, preset.name);
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      }
    }

    // 液态玻璃跟随性能档位：性能档关闭；均衡档标准玻璃；完整动效档增强玻璃。
    switch (preset) {
      case AnimationPreset.performance:
        await LiquidGlassEffectService.setEnabled(false);
      case AnimationPreset.balanced:
        await LiquidGlassEffectService.setEnabled(true);
        await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
      case AnimationPreset.expressive:
        await LiquidGlassEffectService.setEnabled(true);
        await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.enhanced);
    }
  }

  static Future<void> setAnimationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setBool(_keyEnableAnimations, value);
  }

  static Future<void> setMotionBlurEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setBool(_keyEnableMotionBlur, value);
  }

  static Future<void> setLayerBlurEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setBool(_keyEnableLayerBlur, value);
  }

  static Future<void> setLazyLoadEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setBool(_keyEnableLazyLoad, value);
  }

  static Future<void> setScreenRadiusEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setBool(_keyEnableScreenRadius, value);
  }

  static Future<void> setPredictiveBackEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setBool(_keyEnablePredictiveBack, value);
  }

  static Future<void> setAnimationDuration(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setInt(_keyAnimationDuration, value);
  }

  static Future<void> setPageLayerDepth(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setInt(_keyPageLayerDepth, value);
  }

  static Future<void> setContainerContentStart(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
    await prefs.setInt(_keyContainerContentStart, value);
  }

  /// 用户手动微调任一效果（含液态玻璃开关/模式）后调用，
  /// 取消当前性能预设的选中态。
  static Future<void> clearActivePreset() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreset(prefs);
  }

  static Future<void> _clearPreset(SharedPreferences prefs) async {
    await prefs.remove(_keyPreset);
  }
}
