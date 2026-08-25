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
  });

  const LiquidGlassEffectConfiguration.disabled()
      : enabled = false,
        mode = LiquidGlassEffectMode.standard;

  final bool enabled;
  final LiquidGlassEffectMode mode;

  LiquidGlassEffectConfiguration copyWith({
    bool? enabled,
    LiquidGlassEffectMode? mode,
  }) {
    return LiquidGlassEffectConfiguration(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
    );
  }
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

  static final ValueNotifier<LiquidGlassEffectConfiguration>
      _configurationNotifier = ValueNotifier(
    const LiquidGlassEffectConfiguration.disabled(),
  );
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

  static bool get isEnabled => configuration.enabled;

  static LiquidGlassEffectMode get mode => configuration.mode;

  static Future<void> initialize() => _loadFuture ??= _load();

  static Future<LiquidGlassEffectConfiguration> loadConfiguration() async {
    await initialize();
    return configuration;
  }

  static Future<bool> loadEnabled() async {
    await initialize();
    return isEnabled;
  }

  static Future<LiquidGlassEffectMode> loadMode() async {
    await initialize();
    return mode;
  }

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    final mode = LiquidGlassEffectMode.values.firstWhere(
      (candidate) => candidate.name == prefs.getString(_keyMode),
      orElse: () => LiquidGlassEffectMode.standard,
    );
    if (enabled) {
      try {
        await _ensureRendererInitialized(mode: mode);
      } catch (error) {
        debugPrint(
            '[LiquidGlass] Disabled after initialization failed: $error');
        _configurationNotifier.value = LiquidGlassEffectConfiguration(
          enabled: false,
          mode: mode,
        );
        return;
      }
    }
    _configurationNotifier.value = LiquidGlassEffectConfiguration(
      enabled: enabled,
      mode: mode,
    );
  }

  static Future<void> setEnabled(bool enabled) {
    final revision = ++_enabledMutationRevision;
    return _enqueueMutation(() async {
      if (revision != _enabledMutationRevision) return;
      if (enabled) {
        await _ensureRendererInitialized(mode: configuration.mode);
        if (revision != _enabledMutationRevision) return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, enabled);
      if (revision != _enabledMutationRevision) return;
      _configurationNotifier.value = configuration.copyWith(enabled: enabled);
    });
  }

  static Future<void> setMode(LiquidGlassEffectMode mode) {
    final revision = ++_modeMutationRevision;
    return _enqueueMutation(() async {
      if (revision != _modeMutationRevision) return;
      if (isEnabled) {
        await _ensureRendererInitialized(mode: mode);
        if (revision != _modeMutationRevision) return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMode, mode.name);
      if (revision != _modeMutationRevision) return;
      _configurationNotifier.value = configuration.copyWith(mode: mode);
    });
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
