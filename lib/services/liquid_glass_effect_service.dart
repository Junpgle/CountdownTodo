import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_platform.dart';

enum LiquidGlassEffectMode { standard, enhanced }

/// Resolves the glass shader quality for the active platform.
///
/// Windows' Flutter renderer is statically capped at standard quality by the
/// Liquid Glass package. Keep enhanced mode's stronger colors and material
/// treatment, but avoid requesting the unsupported premium capture pipeline.
GlassQuality liquidGlassQualityForMode(LiquidGlassEffectMode mode) {
  if (mode == LiquidGlassEffectMode.enhanced && !AppPlatform.isWindows) {
    return GlassQuality.premium;
  }
  return GlassQuality.standard;
}

@immutable
class LiquidGlassEffectConfiguration {
  const LiquidGlassEffectConfiguration({
    required this.enabled,
    required this.mode,
    this.transparencyPercent = defaultTransparencyPercent,
    this.scrimCoveragePercent = defaultScrimCoveragePercent,
    this.blurSigma = defaultBlurSigma,
  });

  const LiquidGlassEffectConfiguration.disabled()
    : enabled = false,
      mode = LiquidGlassEffectMode.standard,
      transparencyPercent = defaultTransparencyPercent,
      scrimCoveragePercent = defaultScrimCoveragePercent,
      blurSigma = defaultBlurSigma;

  /// Default balanced values: 70% scrim, 35% transparency, 3.0px blur.
  static const int defaultTransparencyPercent = 35;
  static const int defaultScrimCoveragePercent = 70;
  static const double defaultBlurSigma = 3.0;

  final bool enabled;
  final LiquidGlassEffectMode mode;
  final int transparencyPercent;
  final int scrimCoveragePercent;
  final double blurSigma;

  static final Map<int, ui.ImageFilter> _blurFilterCache = {};

  /// Clears cached native ImageFilter instances on memory pressure or background pause.
  static void clearFilterCache() => _blurFilterCache.clear();

  ui.ImageFilter get blurFilter {
    final clamped = blurSigma.clamp(0.001, 50.0);
    final key = (clamped * 100).round();
    return _blurFilterCache.putIfAbsent(
      key,
      () => ui.ImageFilter.blur(
        sigmaX: clamped,
        sigmaY: clamped,
        tileMode: ui.TileMode.clamp,
      ),
    );
  }

  LiquidGlassEffectConfiguration copyWith({
    bool? enabled,
    LiquidGlassEffectMode? mode,
    int? transparencyPercent,
    int? scrimCoveragePercent,
    double? blurSigma,
  }) {
    return LiquidGlassEffectConfiguration(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      transparencyPercent: transparencyPercent ?? this.transparencyPercent,
      scrimCoveragePercent: scrimCoveragePercent ?? this.scrimCoveragePercent,
      blurSigma: blurSigma ?? this.blurSigma,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LiquidGlassEffectConfiguration &&
        other.enabled == enabled &&
        other.mode == mode &&
        other.transparencyPercent == transparencyPercent &&
        other.scrimCoveragePercent == scrimCoveragePercent &&
        (other.blurSigma - blurSigma).abs() < 0.01;
  }

  // blurSigma uses tolerance-based equality above, so omit it to ensure any
  // equal configurations always have the same hash code.
  @override
  int get hashCode =>
      Object.hash(enabled, mode, transparencyPercent, scrimCoveragePercent);
}

/// 0% is opaque, 50% preserves the existing material, and 100% removes the
/// fill. Refraction, highlights, and foreground content remain unchanged.
/// Modulated by [configuration.scrimCoveragePercent] for user-controlled base coverage.
double liquidGlassBackerOpacity(
  double originalOpacity,
  LiquidGlassEffectConfiguration configuration,
) {
  final coverageFactor =
      configuration.scrimCoveragePercent /
      LiquidGlassEffectConfiguration.defaultScrimCoveragePercent;
  final base = (originalOpacity * coverageFactor).clamp(0.0, 1.0).toDouble();
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
  static const String _keyScrimCoverage = 'liquid_glass_scrim_coverage_percent';
  static const String _keyBlurSigma = 'liquid_glass_blur_sigma';
  static const String _keyGuideOffered = 'liquid_glass_guide_offered';

  static final ValueNotifier<LiquidGlassEffectConfiguration>
  _configurationNotifier = ValueNotifier(
    const LiquidGlassEffectConfiguration.disabled(),
  );
  static LiquidGlassEffectConfiguration _preferredConfiguration =
      const LiquidGlassEffectConfiguration.disabled();
  static LiquidGlassEffectConfiguration _persistedConfiguration =
      const LiquidGlassEffectConfiguration.disabled();
  static final ValueNotifier<bool> _hasUnsavedChangesNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> _isSettingsPageActiveNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> _isFloatingPanelExpandedNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> _isLivePreviewForcedNotifier =
      ValueNotifier<bool>(false);

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

  /// The active user choice (including unsaved live preview adjustments).
  static LiquidGlassEffectConfiguration get preferredConfiguration =>
      _preferredConfiguration;

  /// The persisted configuration saved on disk.
  static LiquidGlassEffectConfiguration get persistedConfiguration =>
      _persistedConfiguration;

  /// Whether the user has modified glass parameters without saving.
  static ValueListenable<bool> get hasUnsavedChangesListenable =>
      _hasUnsavedChangesNotifier;

  static bool get hasUnsavedChanges => _hasUnsavedChangesNotifier.value;

  /// Whether the animation settings screen is currently foregrounded.
  static ValueListenable<bool> get isSettingsPageActiveListenable =>
      _isSettingsPageActiveNotifier;

  static bool get isSettingsPageActive => _isSettingsPageActiveNotifier.value;

  static set isSettingsPageActive(bool value) {
    if (_isSettingsPageActiveNotifier.value == value) return;
    _isSettingsPageActiveNotifier.value = value;
  }

  /// Whether the floating adjustment panel is currently expanded to show sliders.
  static ValueListenable<bool> get isFloatingPanelExpandedListenable =>
      _isFloatingPanelExpandedNotifier;

  static bool get isFloatingPanelExpanded =>
      _isFloatingPanelExpandedNotifier.value;

  static set isFloatingPanelExpanded(bool value) {
    if (_isFloatingPanelExpandedNotifier.value == value) return;
    if (WidgetsBinding.instance.buildOwner?.debugBuilding == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isFloatingPanelExpandedNotifier.value = value;
      });
    } else {
      _isFloatingPanelExpandedNotifier.value = value;
    }
  }

  static void toggleFloatingPanel() {
    isFloatingPanelExpanded = !isFloatingPanelExpanded;
  }

  static void expandFloatingPanel() {
    isFloatingPanelExpanded = true;
  }

  static void collapseFloatingPanel() {
    isFloatingPanelExpanded = false;
  }

  /// Whether live preview dock should remain visible even when unsaved changes count is 0.
  static ValueListenable<bool> get isLivePreviewForcedListenable =>
      _isLivePreviewForcedNotifier;

  static bool get isLivePreviewForced => _isLivePreviewForcedNotifier.value;

  static set isLivePreviewForced(bool value) {
    if (_isLivePreviewForcedNotifier.value == value) return;
    _isLivePreviewForcedNotifier.value = value;
  }

  /// Starts live preview mode across all application screens and optionally expands the panel.
  static void startLivePreview({bool expand = true}) {
    isLivePreviewForced = true;
    if (expand) {
      expandFloatingPanel();
    }
  }

  /// Stops live preview mode across screens.
  static void stopLivePreview() {
    isLivePreviewForced = false;
    collapseFloatingPanel();
  }

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
    final transparency =
        (prefs.getInt(_keyTransparency) ??
                LiquidGlassEffectConfiguration.defaultTransparencyPercent)
            .clamp(0, 100);
    final scrimCoverage =
        (prefs.getInt(_keyScrimCoverage) ??
                LiquidGlassEffectConfiguration.defaultScrimCoveragePercent)
            .clamp(0, 100);
    final blurSigma =
        (prefs.getDouble(_keyBlurSigma) ??
                LiquidGlassEffectConfiguration.defaultBlurSigma)
            .clamp(0.0, 30.0);

    _persistedConfiguration = LiquidGlassEffectConfiguration(
      enabled: enabled,
      mode: mode,
      transparencyPercent: transparency,
      scrimCoveragePercent: scrimCoverage,
      blurSigma: blurSigma,
    );
    _preferredConfiguration = _persistedConfiguration;
    _updateUnsavedChanges();

    if (enabled && !_systemPowerSaveMode) {
      try {
        await _ensureRendererInitialized(mode: mode);
      } catch (error) {
        debugPrint(
          '[LiquidGlass] Disabled after initialization failed: $error',
        );
        _preferredConfiguration = _preferredConfiguration.copyWith(
          enabled: false,
        );
        _persistedConfiguration = _persistedConfiguration.copyWith(
          enabled: false,
        );
        _updateUnsavedChanges();
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
      _preferredConfiguration = preferredConfiguration.copyWith(
        enabled: enabled,
      );
      _persistedConfiguration = _persistedConfiguration.copyWith(
        enabled: enabled,
      );
      _updateUnsavedChanges();
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
      _persistedConfiguration = _persistedConfiguration.copyWith(mode: mode);
      _updateUnsavedChanges();
      _publishEffectiveConfiguration();
    });
  }

  static void _updateUnsavedChanges() {
    final changed =
        _preferredConfiguration.transparencyPercent !=
            _persistedConfiguration.transparencyPercent ||
        _preferredConfiguration.scrimCoveragePercent !=
            _persistedConfiguration.scrimCoveragePercent ||
        (_preferredConfiguration.blurSigma - _persistedConfiguration.blurSigma)
                .abs() >
            0.01;
    if (_hasUnsavedChangesNotifier.value != changed) {
      _hasUnsavedChangesNotifier.value = changed;
    }
  }

  /// Updates appearance in real time across the entire application without writing
  /// preferences to disk. Enables live preview while navigating to other pages.
  static void previewAdjustments({
    int? transparencyPercent,
    int? scrimCoveragePercent,
    double? blurSigma,
  }) {
    _preferredConfiguration = _preferredConfiguration.copyWith(
      transparencyPercent: transparencyPercent?.clamp(0, 100),
      scrimCoveragePercent: scrimCoveragePercent?.clamp(0, 100),
      blurSigma: blurSigma?.clamp(0.0, 30.0),
    );
    _updateUnsavedChanges();
    _publishEffectiveConfiguration();
  }

  /// Updates the appearance while dragging without writing preferences for
  /// every slider tick. Persist the settled value with [saveAdjustments].
  static void previewTransparency(int percent) {
    previewAdjustments(transparencyPercent: percent);
  }

  /// Saves current preview adjustments permanently to [SharedPreferences].
  static Future<void> saveAdjustments() {
    final config = _preferredConfiguration;
    collapseFloatingPanel();
    isLivePreviewForced = false;
    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyTransparency, config.transparencyPercent);
      await prefs.setInt(_keyScrimCoverage, config.scrimCoveragePercent);
      await prefs.setDouble(_keyBlurSigma, config.blurSigma);
      _persistedConfiguration = config;
      _updateUnsavedChanges();
    });
  }

  /// Reverts any unsaved preview adjustments back to the last saved configuration.
  static void revertAdjustments() {
    _preferredConfiguration = _persistedConfiguration;
    collapseFloatingPanel();
    isLivePreviewForced = false;
    _updateUnsavedChanges();
    _publishEffectiveConfiguration();
  }

  /// Resets adjustments to the default balanced values (70% scrim, 35% transparency, 3px blur).
  static void resetToDefaults() {
    previewAdjustments(
      transparencyPercent:
          LiquidGlassEffectConfiguration.defaultTransparencyPercent,
      scrimCoveragePercent:
          LiquidGlassEffectConfiguration.defaultScrimCoveragePercent,
      blurSigma: LiquidGlassEffectConfiguration.defaultBlurSigma,
    );
  }

  static Future<void> setTransparency(int percent) {
    final value = percent.clamp(0, 100);
    previewTransparency(value);
    return saveAdjustments();
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
      scrimCoveragePercent: preferred.scrimCoveragePercent,
      blurSigma: preferred.blurSigma,
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

    if (liquidGlassQualityForMode(mode) == GlassQuality.premium) {
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
