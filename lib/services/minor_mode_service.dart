import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/minor_age_signal_state.dart';
import '../models/minor_mode_state.dart';
import '../utils/app_platform.dart';
import 'minor_mode_policy.dart';

class MinorModeService with WidgetsBindingObserver {
  MinorModeService._();

  static final MinorModeService instance = MinorModeService._();

  static const manualEnabledKey = 'minor_mode_manual_enabled';
  static const _channelName = 'com.math_quiz_app/minor_mode';
  static const _eventChannelName = 'com.math_quiz_app/minor_mode_events';

  final MethodChannel _channel = const MethodChannel(_channelName);
  final EventChannel _eventChannel = const EventChannel(_eventChannelName);
  final ValueNotifier<MinorModeState> stateNotifier =
      ValueNotifier(const MinorModeState.unsupported());
  final ValueNotifier<MinorAgeSignalState> googleAgeSignalNotifier =
      ValueNotifier(const MinorAgeSignalState.unavailable());

  StreamSubscription<dynamic>? _eventSubscription;
  Future<void>? _initialization;
  bool _initialized = false;
  bool _hasPlatformState = false;
  MinorModeAction? _cachedAuthorizedAction;
  String? _cachedAuthorizationFingerprint;
  DateTime? _cachedAuthorizationExpiresAt;

  static const _parentAuthorizationSession = Duration(minutes: 5);

  MinorModeState get state => stateNotifier.value;
  MinorModeState get policyState {
    final ageSignal = googleAgeSignalNotifier.value;
    if (!ageSignal.isMinor) return state;
    return state.copyWith(
      systemSupported: true,
      systemEnabled: true,
      source: MinorModeSource.googleAgeSignals,
      ageBand: ageSignal.ageBand,
      lastError: state.lastError,
    );
  }

  bool get effectiveMinorMode => policyState.effectiveMinorMode;

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;

    if (!AppPlatform.isAndroid) {
      await _applyManualState();
      return;
    }

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handlePlatformEvent,
      onError: (Object error, StackTrace stackTrace) {
        _markPlatformReadFailed(error);
      },
    );
    await refreshMinorModeState();
    await refreshGoogleAgeSignalState();
  }

  Future<MinorModeState> refreshMinorModeState() async {
    if (!_initialized) await initialize();
    final manualEnabled = await _readManualEnabled();

    if (!AppPlatform.isAndroid) {
      return _publish(
        MinorModeState.unsupported(manualEnabled: manualEnabled),
      );
    }

    try {
      final raw = await _channel.invokeMethod<dynamic>('refreshMinorModeState');
      if (raw is Map) {
        final map = Map<Object?, Object?>.from(raw);
        _hasPlatformState = true;
        return _publish(
          MinorModeState.fromPlatformMap(
            map,
            manualEnabled: manualEnabled,
          ),
        );
      }
      throw const FormatException('Invalid minor mode state response');
    } on MissingPluginException catch (error) {
      return _handlePlatformFailure(error, manualEnabled);
    } on PlatformException catch (error) {
      return _handlePlatformFailure(error, manualEnabled);
    } catch (error) {
      return _handlePlatformFailure(error, manualEnabled);
    }
  }

  Future<MinorModeState> setManualEnabled(bool enabled) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(manualEnabledKey, enabled);

    final current = state;
    return _publish(
      current.copyWith(
        manualEnabled: enabled,
        source: current.systemEnabled
            ? current.source
            : enabled
                ? MinorModeSource.manual
                : current.systemSupported
                    ? MinorModeSource.chinaSystem
                    : MinorModeSource.unsupported,
        lastError: current.lastError,
      ),
    );
  }

  Future<MinorAgeSignalState> refreshGoogleAgeSignalState() async {
    if (!_initialized) await initialize();
    if (!AppPlatform.isAndroid) {
      return _publishGoogleAgeSignal(const MinorAgeSignalState.unavailable());
    }

    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'refreshGoogleAgeSignals',
      );
      if (raw is Map) {
        return _publishGoogleAgeSignal(
          MinorAgeSignalState.fromPlatformMap(
            Map<Object?, Object?>.from(raw),
          ),
        );
      }
      throw const FormatException('Invalid Google age signals response');
    } on MissingPluginException catch (error) {
      return _publishGoogleAgeSignal(
        _googleAgeSignalFailure(error),
      );
    } on PlatformException catch (error) {
      return _publishGoogleAgeSignal(
        _googleAgeSignalFailure(error),
      );
    } catch (error) {
      return _publishGoogleAgeSignal(
        _googleAgeSignalFailure(error),
      );
    }
  }

  Future<MinorAgeSignalState> requestGoogleAgeSignals() async {
    await initialize();
    if (!AppPlatform.isAndroid) {
      return _publishGoogleAgeSignal(const MinorAgeSignalState.unavailable());
    }

    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'requestGoogleAgeSignals',
      );
      if (raw is Map) {
        return _publishGoogleAgeSignal(
          MinorAgeSignalState.fromPlatformMap(
            Map<Object?, Object?>.from(raw),
          ),
        );
      }
      throw const FormatException('Invalid Google age signals response');
    } on MissingPluginException catch (error) {
      return _publishGoogleAgeSignal(
        _googleAgeSignalFailure(error),
      );
    } on PlatformException catch (error) {
      return _publishGoogleAgeSignal(
        _googleAgeSignalFailure(error),
      );
    } catch (error) {
      return _publishGoogleAgeSignal(
        _googleAgeSignalFailure(error),
      );
    }
  }

  Future<bool> requestParentAuthentication() async {
    if (!AppPlatform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestParentAuthentication',
      );
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authorizeAction(MinorModeAction action) async {
    await initialize();
    final current = policyState;
    if (!MinorModePolicy.isAllowedByAge(current, action)) return false;
    if (!MinorModePolicy.requiresParentAuthenticationFor(current, action)) {
      return true;
    }
    if (MinorModePolicy.allowWhenParentAuthenticationUnavailable(current)) {
      return true;
    }
    if (_hasCachedAuthorization(action, current)) return true;

    final authorized = await requestParentAuthentication();
    if (authorized) {
      _cachedAuthorizedAction = action;
      _cachedAuthorizationFingerprint = _authorizationFingerprint(current);
      _cachedAuthorizationExpiresAt =
          DateTime.now().add(_parentAuthorizationSession);
    }
    return authorized;
  }

  Future<bool> authorizeSensitiveAction({
    MinorModeAction action = MinorModeAction.sensitive,
  }) async {
    return authorizeAction(action);
  }

  Future<bool> authorizeAiInteraction() async {
    return authorizeAction(MinorModeAction.aiInteraction);
  }

  Future<bool> canUseAiInteraction() async {
    await initialize();
    return MinorModePolicy.isAllowedByAge(
      policyState,
      MinorModeAction.aiInteraction,
    );
  }

  String authorizationFailureMessage(MinorModeAction action) {
    return MinorModePolicy.denialMessage(policyState, action);
  }

  Future<bool> isParentAuthenticationSupported() async {
    if (!AppPlatform.isAndroid) return false;
    try {
      final supported = await _channel.invokeMethod<bool>(
        'isParentAuthenticationSupported',
      );
      return supported == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openMinorModeSettings() async {
    if (!AppPlatform.isAndroid) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openMinorModeSettings');
      return opened == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _initialized) {
      unawaited(refreshMinorModeState());
      unawaited(refreshGoogleAgeSignalState());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _clearAuthorizationCache();
    }
  }

  Future<bool> _readManualEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(manualEnabledKey) ?? false;
    } catch (_) {
      return state.manualEnabled;
    }
  }

  Future<void> _applyManualState() async {
    final manualEnabled = await _readManualEnabled();
    _publish(MinorModeState.unsupported(manualEnabled: manualEnabled));
  }

  void _handlePlatformEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<Object?, Object?>.from(event);
    unawaited(_applyPlatformEvent(map));
  }

  Future<void> _applyPlatformEvent(Map<Object?, Object?> map) async {
    final manualEnabled = await _readManualEnabled();
    _hasPlatformState = true;
    _publish(
      MinorModeState.fromPlatformMap(
        map,
        manualEnabled: manualEnabled,
      ),
    );
  }

  MinorModeState _handlePlatformFailure(Object error, bool manualEnabled) {
    if (_hasPlatformState) {
      return _publish(
        state.copyWith(
          manualEnabled: manualEnabled,
          systemStateReadFailed: true,
          lastError: error.toString(),
        ),
      );
    }
    return _publish(
      MinorModeState.unsupported(
        manualEnabled: manualEnabled,
        systemStateReadFailed: true,
        lastError: error.toString(),
      ),
    );
  }

  MinorAgeSignalState _googleAgeSignalFailure(Object error) {
    return MinorAgeSignalState(
      available: false,
      status: MinorAgeSignalStatus.error,
      lastError: error.toString(),
    );
  }

  void _markPlatformReadFailed(Object error) {
    if (!_hasPlatformState) return;
    _publish(
      state.copyWith(
        systemStateReadFailed: true,
        lastError: error.toString(),
      ),
    );
  }

  MinorModeState _publish(MinorModeState nextState) {
    if (nextState != state) _clearAuthorizationCache();
    stateNotifier.value = nextState;
    return nextState;
  }

  MinorAgeSignalState _publishGoogleAgeSignal(MinorAgeSignalState nextState) {
    if (nextState != googleAgeSignalNotifier.value) {
      _clearAuthorizationCache();
    }
    googleAgeSignalNotifier.value = nextState;
    return nextState;
  }

  bool _hasCachedAuthorization(
    MinorModeAction action,
    MinorModeState current,
  ) {
    final expiresAt = _cachedAuthorizationExpiresAt;
    return _cachedAuthorizedAction == action &&
        _cachedAuthorizationFingerprint == _authorizationFingerprint(current) &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt);
  }

  String _authorizationFingerprint(MinorModeState current) =>
      '${current.effectiveMinorMode}:${current.source.name}:${current.ageBand.name}:${current.systemEnabled}:${current.manualEnabled}';

  void _clearAuthorizationCache() {
    _cachedAuthorizedAction = null;
    _cachedAuthorizationFingerprint = null;
    _cachedAuthorizationExpiresAt = null;
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _initialization = null;
    _initialized = false;
    _hasPlatformState = false;
    _clearAuthorizationCache();
    _publishGoogleAgeSignal(const MinorAgeSignalState.unavailable());
  }
}
