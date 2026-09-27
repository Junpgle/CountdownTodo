import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LiquidGlassEffectMode {
  standard,
  enhanced,
}

@immutable
class LiquidGlassEffectConfiguration {
  const LiquidGlassEffectConfiguration({
    required this.enabled,
    required this.mode,
    this.transparencyPercent = defaultTransparencyPercent,
  });

  const LiquidGlassEffectConfiguration.disabled()
      : enabled = false,
        mode = LiquidGlassEffectMode.standard,
        transparencyPercent = defaultTransparencyPercent;

  /// Keeps existing glass colors unchanged until the user moves the slider.
  static const int defaultTransparencyPercent = 50;

  final bool enabled;
  final LiquidGlassEffectMode mode;
  final int transparencyPercent;

  LiquidGlassEffectConfiguration copyWith({
    bool? enabled,
    LiquidGlassEffectMode? mode,
    int? transparencyPercent,
  }) {
    return LiquidGlassEffectConfiguration(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      transparencyPercent: transparencyPercent ?? this.transparencyPercent,
    );
  }
}

/// 0% is opaque, 50% preserves the existing material, and 100% removes the
/// fill. Refraction, highlights, and foreground content remain unchanged.
double liquidGlassBackerOpacity(
  double originalOpacity,
  LiquidGlassEffectConfiguration configuration,
) {
  final base = originalOpacity.clamp(0.0, 1.0).toDouble();
  final transparency = configuration.transparencyPercent.clamp(0, 100) / 100;
  if (transparency <= 0.5) {
    return 1.0 + (base - 1.0) * (transparency * 2);
  }
  return base * (1.0 - (transparency - 0.5) * 2);
}

class _LiquidGlassMutation {
  const _LiquidGlassMutation(this.run, this.completer);

  final Future<void> Function() run;
  final Completer<void> completer;
}

/// Owns the optional Liquid Glass preference and initializes its shaders only
/// when the effect is actually enabled.
class LiquidGlassEffectService {
  LiquidGlassEffectService._();

  static const String _keyEnabled = 'enable_liquid_glass';
  static const String _keyMode = 'liquid_glass_effect_mode';
  static const String _keyTransparency = 'liquid_glass_transparency_percent';
  static const String _keyGuideOffered = 'liquid_glass_guide_offered';

  static final ValueNotifier<LiquidGlassEffectConfiguration>
      _configurationNotifier = ValueNotifier(
    const LiquidGlassEffectConfiguration.disabled(),
  );
  static LiquidGlassEffectConfiguration _preferredConfiguration =
      const LiquidGlassEffectConfiguration.disabled();
  static bool _systemPowerSaveMode = false;
  static Future<void>? _loadFuture;
  static Future<void>? _rendererInitialization;
  static Future<void>? _premiumRendererInitialization;
  static bool _rendererInitialized = false;
  static bool _premiumRendererInitialized = false;
  static final List<_LiquidGlassMutation> _mutationQueue = [];
  static bool _mutationQueueRunning = false;
  static int _enabledMutationRevision = 0;
  static int _modeMutationRevision = 0;

  static ValueListenable<LiquidGlassEffectConfiguration>
      get configurationListenable => _configurationNotifier;

  static LiquidGlassEffectConfiguration get configuration =>
      _configurationNotifier.value;

  /// The persisted user choice, independent of the temporary system override.
  static LiquidGlassEffectConfiguration get preferredConfiguration =>
      _preferredConfiguration;

  static bool get isEnabled => configuration.enabled;

  static LiquidGlassEffectMode get mode => configuration.mode;

  static Future<void> initialize() => _loadFuture ??= _load();

  static Future<LiquidGlassEffectConfiguration> loadConfiguration() async {
    if (_loadFuture != null) return preferredConfiguration;
    await initialize();
    return preferredConfiguration;
  }

  static Future<bool> loadEnabled() async {
    // 加载已完成时直接读取当前配置；跨事件循环区域等待已完成的缓存
    // Future 在测试等自定义 Zone 下可能永不恢复。
    if (_loadFuture != null) return preferredConfiguration.enabled;
    await initialize();
    return preferredConfiguration.enabled;
  }

  static Future<LiquidGlassEffectMode> loadMode() async {
    if (_loadFuture != null) return preferredConfiguration.mode;
    await initialize();
    return preferredConfiguration.mode;
  }

  /// 引导页是否已经向用户展示过液态玻璃选项（展示一次，不重复打扰）。
  static Future<bool> isGuideOfferDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGuideOffered) ?? false;
  }

  static Future<void> markGuideOffered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuideOffered, true);
  }

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    final mode = LiquidGlassEffectMode.values.firstWhere(
      (candidate) => candidate.name == prefs.getString(_keyMode),
      orElse: () => LiquidGlassEffectMode.standard,
    );
    _preferredConfiguration = LiquidGlassEffectConfiguration(
      enabled: enabled,
      mode: mode,
      transparencyPercent: (prefs.getInt(_keyTransparency) ??
              LiquidGlassEffectConfiguration.defaultTransparencyPercent)
          .clamp(0, 100),
    );
    if (enabled && !_systemPowerSaveMode) {
      try {
        await _ensureRendererInitialized(mode: mode);
      } catch (error) {
        debugPrint(
            '[LiquidGlass] Disabled after initialization failed: $error');
        _preferredConfiguration = LiquidGlassEffectConfiguration(
          enabled: false,
          mode: mode,
          transparencyPercent: _preferredConfiguration.transparencyPercent,
        );
        _publishEffectiveConfiguration();
        return;
      }
    }
    _publishEffectiveConfiguration();
  }

  static Future<void> setEnabled(bool enabled) {
    final revision = ++_enabledMutationRevision;
    return _enqueueMutation(() async {
      if (revision != _enabledMutationRevision) return;
      if (enabled && !_systemPowerSaveMode) {
        await _ensureRendererInitialized(mode: preferredConfiguration.mode);
        if (revision != _enabledMutationRevision) return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, enabled);
      if (revision != _enabledMutationRevision) return;
      _preferredConfiguration =
          preferredConfiguration.copyWith(enabled: enabled);
      _publishEffectiveConfiguration();
    });
  }

  static Future<void> setMode(LiquidGlassEffectMode mode) {
    final revision = ++_modeMutationRevision;
    return _enqueueMutation(() async {
      if (revision != _modeMutationRevision) return;
      if (preferredConfiguration.enabled && !_systemPowerSaveMode) {
        await _ensureRendererInitialized(mode: mode);
        if (revision != _modeMutationRevision) return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMode, mode.name);
      if (revision != _modeMutationRevision) return;
      _preferredConfiguration = preferredConfiguration.copyWith(mode: mode);
      _publishEffectiveConfiguration();
    });
  }

  /// Updates the appearance while dragging without writing preferences for
  /// every slider tick. Persist the settled value with [setTransparency].
  static void previewTransparency(int percent) {
    _preferredConfiguration = preferredConfiguration.copyWith(
      transparencyPercent: percent.clamp(0, 100),
    );
    _publishEffectiveConfiguration();
  }

  static Future<void> setTransparency(int percent) {
    final value = percent.clamp(0, 100);
    previewTransparency(value);
    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyTransparency, value);
    });
  }

  /// Temporarily suppresses shader-backed glass while Android Battery Saver is
  /// active. The user's preference remains persisted and is restored when the
  /// system exits Battery Saver.
  static Future<void> setPowerSaveMode(bool enabled) async {
    final stateChanged = _systemPowerSaveMode != enabled;
    _systemPowerSaveMode = enabled;

    if (enabled) {
      _publishEffectiveConfiguration();
      return;
    }

    if (!stateChanged &&
        (!preferredConfiguration.enabled || configuration.enabled)) {
      return;
    }

    if (preferredConfiguration.enabled) {
      try {
        await _ensureRendererInitialized(mode: preferredConfiguration.mode);
      } catch (error) {
        debugPrint('[LiquidGlass] Restore after Battery Saver failed: $error');
        return;
      }
      if (_systemPowerSaveMode) return;
    }
    _publishEffectiveConfiguration();
  }

  static void _publishEffectiveConfiguration() {
    final preferred = preferredConfiguration;
    _configurationNotifier.value = LiquidGlassEffectConfiguration(
      enabled: preferred.enabled && !_systemPowerSaveMode,
      mode: preferred.mode,
      transparencyPercent: preferred.transparencyPercent,
    );
  }

  static Future<void> _enqueueMutation(Future<void> Function() mutation) {
    final completer = Completer<void>();
    _mutationQueue.add(_LiquidGlassMutation(mutation, completer));
    if (!_mutationQueueRunning) {
      _mutationQueueRunning = true;
      unawaited(_drainMutationQueue());
    }
    return completer.future;
  }

  static Future<void> _drainMutationQueue() async {
    while (_mutationQueue.isNotEmpty) {
      final mutation = _mutationQueue.removeAt(0);
      try {
        await mutation.run();
        mutation.completer.complete();
      } catch (error, stackTrace) {
        mutation.completer.completeError(error, stackTrace);
      }
    }
    _mutationQueueRunning = false;
  }

  static Future<void> _ensureRendererInitialized({
    required LiquidGlassEffectMode mode,
  }) async {
    if (!_rendererInitialized) {
      final existing = _rendererInitialization;
      if (existing != null) {
        await existing;
      } else {
        final initialization = LiquidGlassWidgets.initialize(
          warmUpMode: GlassWarmUpMode.never,
        );
        _rendererInitialization = initialization;
        try {
          await initialization;
          _rendererInitialized = true;
        } catch (_) {
          if (identical(_rendererInitialization, initialization)) {
            _rendererInitialization = null;
          }
          rethrow;
        }
      }
    }

    if (mode == LiquidGlassEffectMode.enhanced) {
      await _ensurePremiumRendererInitialized();
    }
  }

  static Future<void> _ensurePremiumRendererInitialized() async {
    if (_premiumRendererInitialized) return;

    final existing = _premiumRendererInitialization;
    if (existing != null) {
      await existing;
      return;
    }

    // Auto preloads the Premium pipeline on Android/iOS/macOS while retaining
    // the package's Standard fallback on Web, Windows, and Linux. Complete the
    // preload before publishing enhanced mode so the first visible frame does
    // not briefly render without its glass backing.
    final initialization = LiquidGlassWidgets.initialize(
      warmUpMode: GlassWarmUpMode.auto,
    );
    _premiumRendererInitialization = initialization;
    try {
      await initialization;
      _premiumRendererInitialized = true;
    } catch (_) {
      if (identical(_premiumRendererInitialization, initialization)) {
        _premiumRendererInitialization = null;
      }
      rethrow;
    }
  }
}
