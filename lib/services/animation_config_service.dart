import 'package:shared_preferences/shared_preferences.dart';

class AnimationConfigService {
  static const String _keyEnableAnimations = 'enable_animations';
  static const String _keyEnableMotionBlur = 'enable_motion_blur';
  static const String _keyEnableLayerBlur = 'enable_layer_blur';
  static const String _keyEnableLazyLoad = 'enable_lazy_load';
  static const String _keyEnableScreenRadius = 'enable_screen_radius';
  static const String _keyEnablePredictiveBack = 'enable_predictive_back';
  static const String _keyAnimationDuration = 'animation_duration';

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
    return prefs.getInt(_keyAnimationDuration) ?? 500;
  }

  static Future<void> setAnimationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableAnimations, value);
  }

  static Future<void> setMotionBlurEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableMotionBlur, value);
  }

  static Future<void> setLayerBlurEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableLayerBlur, value);
  }

  static Future<void> setLazyLoadEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableLazyLoad, value);
  }

  static Future<void> setScreenRadiusEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableScreenRadius, value);
  }

  static Future<void> setPredictiveBackEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnablePredictiveBack, value);
  }

  static Future<void> setAnimationDuration(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAnimationDuration, value);
  }
}
