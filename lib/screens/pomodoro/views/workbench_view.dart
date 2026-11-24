import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../models.dart';
import '../../../storage_service.dart';
import '../../../utils/app_dialogs.dart';
import '../../../widgets/settings_focus_page.dart';
import '../../../services/pomodoro_service.dart';
import '../../../services/pomodoro_control_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/android_window_rendering_policy.dart';
import '../../../services/scheduled_reminder_registry.dart';
import '../../../services/pomodoro_sync_service.dart';
import '../../../services/focus_do_not_disturb_service.dart';
import '../../../services/strict_focus_sensor_service.dart';
import '../../../services/strict_focus_haptic_service.dart';
import '../../../services/strict_focus_session_coordinator.dart';
import '../../../services/todo_classification_service.dart';
import '../../../services/band_sync_service.dart';
import '../../../services/float_window_service.dart';
import '../../../services/island_action_channel.dart';
import '../../../services/macos_pomodoro_status_bar_service.dart';
import '../../../services/window_focus_service.dart';
import '../../../update_service.dart';
import '../../../utils/app_color_utils.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/page_transitions.dart';
import '../../../utils/todo_recurrence_picker.dart';
import '../../../features/habits/services/habit_focus_completion_service.dart';
import '../pomodoro_entry_intent.dart';
import '../unified_tag_manager_screen.dart';
import '../widgets/immersive_timer.dart';
import '../widgets/workbench_actions.dart';
import '../widgets/workbench_task_area.dart';

part 'parts/workbench_sync_and_recovery.dart';
part 'parts/workbench_session_controls.dart';
part 'parts/workbench_dialogs.dart';
part 'parts/workbench_layout.dart';

const _keyBoundTodoUuid = 'pomodoro_idle_bound_todo_uuid';
const _keyBoundTodoTitle = 'pomodoro_idle_bound_todo_title';
const _keySelectedTagUuids = 'pomodoro_idle_selected_tag_uuids';

class PomodoroWorkbench extends StatefulWidget {
  final String username;
  final PomodoroEntryIntent? initialEntry;
  final ValueChanged<PomodoroPhase> onPhaseChanged;
  final VoidCallback? onReady;
  final VoidCallback? onRecordAdded;

  // New: allow the workbench to render in a compact mode (used by landscape side column)
  final bool isCompact;

  const PomodoroWorkbench({
    super.key,
    required this.username,
    this.initialEntry,
    required this.onPhaseChanged,
    this.onReady,
    this.onRecordAdded,
    this.isCompact = false,
  });

  @override
  State<PomodoroWorkbench> createState() => PomodoroWorkbenchState();
}

class PomodoroWorkbenchState extends State<PomodoroWorkbench>
    with WidgetsBindingObserver {
  // ── 设置 ──
  PomodoroSettings _settings = PomodoroSettings();

  // ── 运行状态 ──
  PomodoroPhase _phase = PomodoroPhase.idle;
  String _currentSessionUuid = '';
  bool _isHandlingEnd = false;

  int _targetEndMs = 0;
  int _remainingSeconds = 0;
  int _currentCycle = 1;
  int _sessionStartMs = 0;
  int? _activeFocusSeconds;
  int? _preparedFocusMinutes;
  String? _planBlockId;
  String? _habitUuid;
  int? _challengeTaskId;
  String? _targetLabel;
  (TodoPlanBlock, TodoPlanStatus)? _strictWaitPlanStatusReceipt;
  bool _initialEntryApplied = false;

  // 🚀 暂停状态
  bool _isPaused = false;
  int _pausedAtMs = 0;
  int _accumulatedMs = 0;
  int _pauseStartMs = 0;
  int _pauseElapsedSecs = 0;
  Timer? _pauseTicker;
  final List<PauseInterval> _pauseIntervals = [];

  // ── 任务绑定 ──
  TodoItem? _boundTodo;
  List<PomodoroTag> _allTags = []; // 所有标签（包括归档）
  List<PomodoroTag> _tags = []; // 未归档标签（用于显示）
  List<String> _selectedTagUuids = [];

  // ── Timer ──
  Timer? _ticker;
  final ValueNotifier<int> _timerTickNotifier = ValueNotifier<int>(0);
  bool _appInForeground = true;
  bool _tickerModeEnabled = true;

  bool get _shouldRunUiTickers =>
      _appInForeground && _tickerModeEnabled && mounted;

  // ── 严格自由专注传感器 ──
  StreamSubscription<StrictFocusSensorEvent>? _strictSensorSub;
  StrictFocusSensorState _strictSensorState =
      StrictFocusSensorState.waitingForFaceUp;
  bool _strictWaitingForFlip = false;
  bool _strictStartInFlight = false;
  bool _normalFocusStartInFlight = false;
  bool _strictUnavailableNoticeShown = false;

  // ── Todos ──
  List<TodoItem> _todos = [];
  List<TodoGroup> _todoGroups = [];
  String _deviceId = '';
  String _userId = '';
  String _appVersion = 'unknown';

  // ── 专注备注 ──
  String _currentNote = '';

  // ── 跨端感知 ──
  final _syncService = PomodoroSyncService();
  void Function(CrossDevicePomodoroState)? _staleSyncFocusHandler;
  StreamSubscription? _crossDeviceSub;
  StreamSubscription? _connSub; // 🚀 兼容性修复：改为通配订阅类型
  CrossDevicePomodoroState? _remoteState;

  // ── Coach Mark Keys ──
  // 竖屏与横屏布局会在方向切换的 AnimatedSwitcher 渐变期间短暂共存，
  // 因此每个方向各持有一套 Key 实例，getters 暴露当前挂载布局的那一套。
  final GlobalKey _portraitSettingsKey = GlobalKey();
  final GlobalKey _portraitTagsManagerKey = GlobalKey();
  final GlobalKey _portraitServerConnKey = GlobalKey();
  final GlobalKey _portraitModeSwitchKey = GlobalKey();
  final GlobalKey _portraitFocusTagsKey = GlobalKey();
  final GlobalKey _portraitBindTodoKey = GlobalKey();
  // The idle and active layouts overlap briefly during their transition.
  final GlobalKey _portraitActiveBindTodoKey = GlobalKey();
  final GlobalKey _landscapeSettingsKey = GlobalKey();
  final GlobalKey _landscapeTagsManagerKey = GlobalKey();
  final GlobalKey _landscapeServerConnKey = GlobalKey();
  final GlobalKey _landscapeModeSwitchKey = GlobalKey();
  final GlobalKey _landscapeFocusTagsKey = GlobalKey();
  final GlobalKey _landscapeBindTodoKey = GlobalKey();
  final GlobalKey _landscapeActiveBindTodoKey = GlobalKey();
  bool _landscapeLayoutMounted = false;

  GlobalKey get settingsKey =>
      _landscapeLayoutMounted ? _landscapeSettingsKey : _portraitSettingsKey;
  GlobalKey get tagsManagerKey => _landscapeLayoutMounted
      ? _landscapeTagsManagerKey
      : _portraitTagsManagerKey;
  GlobalKey get serverConnKey => _landscapeLayoutMounted
      ? _landscapeServerConnKey
      : _portraitServerConnKey;
  GlobalKey get modeSwitchKey => _landscapeLayoutMounted
      ? _landscapeModeSwitchKey
      : _portraitModeSwitchKey;
  GlobalKey get focusTagsKey =>
      _landscapeLayoutMounted ? _landscapeFocusTagsKey : _portraitFocusTagsKey;
  GlobalKey get bindTodoKey {
    final isIdle =
        _phase == PomodoroPhase.idle || _phase == PomodoroPhase.finished;
    if (_landscapeLayoutMounted) {
      return isIdle ? _landscapeBindTodoKey : _landscapeActiveBindTodoKey;
    }
    return isIdle ? _portraitBindTodoKey : _portraitActiveBindTodoKey;
  }

  Timer? _remoteTicker;
  List<String> _remoteTagNames = [];

  SyncConnectionState _syncConnState =
      SyncConnectionState.disconnected; // 🚀 新增：跟踪连接状态
  bool _hasShownUpdate = false;
  bool _initializing = true;
  bool? _systemDoNotDisturbAccess;
  PomodoroCommunityStats? _communityStats;
  bool _isInitProcessing = false;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appInForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    FloatWindowService.isWorkbenchMounted = true;
    WidgetsBinding.instance.addObserver(this);
    MacPomodoroStatusBarService.init();
    _init();
    unawaited(_loadCommunityStats());
    _listenToRunState();
    _listenToStrictSensor();
    _listenToIslandActions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    if (_tickerModeEnabled == tickerModeEnabled) return;

    _tickerModeEnabled = tickerModeEnabled;
    if (_shouldRunUiTickers) {
      unawaited(_resumeUiTickers());
    } else {
      _stopUiTickers();
    }
  }

  StreamSubscription? _islandSub;
  StreamSubscription? _bandSub;
  StreamSubscription? _macStatusBarSub;
  void _listenToIslandActions() {
    _islandSub = IslandActionChannel.actionStream.listen((actionData) {
      if (!mounted) return;
      if (actionData.isNotEmpty) {
        final action = actionData['action']?.toString();
        if (action == 'finish') {
          WindowFocusService.showAndFocus();
          _onFocusEnd();
        } else if (action == 'abandon') {
          WindowFocusService.showAndFocus();
          _abandonFocus(true);
        }
      }
    });
    _bandSub = BandSyncService.onBandPomodoroAction.listen((actionData) {
      if (!mounted) return;
      final action = actionData['action']?.toString();
      if (action == 'finish') {
        if (!AppPlatform.isWindows) {
          _finishEarly();
        } else {
          WindowFocusService.showAndFocus();
          _finishEarly();
        }
      } else if (action == 'abandon') {
        if (!AppPlatform.isWindows) {
          _abandonFocus(true);
        } else {
          WindowFocusService.showAndFocus();
          _abandonFocus(true);
        }
      }
    });
    // 监听 macOS 状态栏操作
    if (AppPlatform.isMacOS) {
      _macStatusBarSub = MacPomodoroStatusBarService.onAction.listen((action) {
        if (!mounted) return;
        switch (action) {
          case MacPomodoroAction.togglePause:
            handleTogglePause();
          case MacPomodoroAction.stopFocus:
            handleStopFocus();
        }
      });
    }
  }

  StreamSubscription? _runStateSub;
  bool _suppressRunStateEvents = false;
  void _listenToRunState() {
    _runStateSub = PomodoroService.onRunStateChanged.listen((state) {
      if (_suppressRunStateEvents || _isHandlingEnd) return;
      if (state == null &&
          (_phase == PomodoroPhase.focusing ||
              _phase == PomodoroPhase.breaking)) {
        // Island action (finish/abandon) cleared the state, we must sync UI
        _ticker?.cancel();
        NotificationService.cancelNotification();
        unawaited(_setFocusDoNotDisturb(false, force: true));
        if (mounted) {
          setState(() {
            _phase = PomodoroPhase.idle;
            _remainingSeconds = _settings.mode == TimerMode.countUp
                ? 0
                : _settings.focusMinutes * 60;
          });
          widget.onPhaseChanged(_phase);
          // Force full UI reload to reflect completed/abandoned session
          _init();
        }
      } else if (state != null &&
          state.phase != PomodoroPhase.idle &&
          state.phase != PomodoroPhase.finished &&
          (_phase == PomodoroPhase.idle ||
              _phase == PomodoroPhase.finished ||
              _currentSessionUuid != state.sessionUuid)) {
        _recoverState(state);
      } else if (state != null &&
          state.sessionUuid == _currentSessionUuid &&
          state.phase == PomodoroPhase.focusing &&
          _phase == PomodoroPhase.focusing) {
        _applySavedFocusState(state);
      }
    });
  }

  void _listenToStrictSensor() {
    _strictSensorSub = StrictFocusSessionCoordinator.instance.sensorEvents
        .listen((event) {
          _handleStrictSensorEvent(event);
        });
  }

  void _applySavedFocusState(PomodoroRunState state) {
    if (!mounted) return;
    final wasPaused = _isPaused;
    final wasWaitingForFlip = _strictWaitingForFlip;
    setState(() {
      _targetEndMs = state.targetEndMs;
      _sessionStartMs = state.sessionStartMs;
      _isPaused = state.isPaused;
      _strictWaitingForFlip = state.strictWaitingForFlip;
      _pausedAtMs = state.pausedAtMs;
      _pauseStartMs = state.pauseStartMs;
      _accumulatedMs = state.accumulatedMs;
      _pauseIntervals
        ..clear()
        ..addAll(state.pauseIntervals);
    });

    if (state.isPaused && !wasPaused) {
      _ticker?.cancel();
      _startPauseTicker();
    } else if (!state.isPaused && wasPaused) {
      _pauseTicker?.cancel();
      _startTicker();
    }
    if (wasWaitingForFlip != state.strictWaitingForFlip) {
      _timerTickNotifier.value++;
    }
    _timerTickNotifier.value++;
  }

  Future<void> _clearRunStateSilently() async {
    _suppressRunStateEvents = true;
    try {
      await PomodoroService.clearRunState();
      await NotificationService.reconcileScheduledRemindersForDoNotDisturb();
      await Future<void>.delayed(Duration.zero);
    } finally {
      _suppressRunStateEvents = false;
    }
  }

  Future<void> _setFocusDoNotDisturb(
    bool active, {
    String? sessionUuid,
    int? untilMs,
    bool force = false,
  }) async {
    await FocusDoNotDisturbService.setActive(
      active,
      sessionUuid: sessionUuid,
      untilMs: untilMs,
      force: force,
    );
    await NotificationService.reconcileScheduledRemindersForDoNotDisturb();
  }

  Future<void> _refreshSystemDoNotDisturbAccess() async {
    if (!FocusDoNotDisturbService.supportsSystemDoNotDisturb) return;
    final access = await FocusDoNotDisturbService.hasSystemDoNotDisturbAccess();
    if (mounted) setState(() => _systemDoNotDisturbAccess = access);
  }

  @override
  void dispose() {
    FloatWindowService.isWorkbenchMounted = false;
    _ticker?.cancel();
    _pauseTicker?.cancel();
    _remoteTicker?.cancel();
    _timerTickNotifier.dispose();
    if (_staleSyncFocusHandler != null) {
      _syncService.unregisterStaleSyncFocusHandler(_staleSyncFocusHandler!);
      _staleSyncFocusHandler = null;
    }
    _crossDeviceSub?.cancel();
    _connSub?.cancel();
    _runStateSub?.cancel();
    _strictSensorSub?.cancel();
    _islandSub?.cancel();
    _bandSub?.cancel();
    _macStatusBarSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Public API: reload workbench data (used by parent when tab becomes visible)
  Future<void> reload() async {
    // Re-run the initialization sequence to refresh settings/tags/state
    await _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      _stopUiTickers();
      if (state != AppLifecycleState.inactive) {
        unawaited(_syncService.suspendForBackground());
      }
      if (_isHandlingEnd) return;
      if (state != AppLifecycleState.inactive) {
        if (_strictWaitingForFlip) {
          StrictFocusSessionCoordinator.instance.pauseForBackground();
        } else if (_isStrictFreeFocus &&
            _phase == PomodoroPhase.focusing &&
            !_isPaused) {
          // 严格模式在前台失去传感器数据时安全暂停，避免把后台时间算进专注。
          StrictFocusSessionCoordinator.instance.pauseForBackground();
        }
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      unawaited(_refreshSystemDoNotDisturbAccess());
      unawaited(_resumeUiTickers());
      unawaited(_syncService.resumeFromBackground());
      if (_isStrictFreeFocus && _phase == PomodoroPhase.focusing && _isPaused) {
        if (!StrictFocusSessionCoordinator.instance.isMonitoring) {
          StrictFocusSessionCoordinator.instance.startMonitoring(
            requireInitialFaceUp: false,
          );
        }
      }
    }
  }

  // 公开方法：供外部调用提前完成
  void handleFinishEarly() {
    // Android notification actions mean “finish this Pomodoro”, not “finish
    // this focus round and start its break”. Keep the confirmation dialog,
    // but do not restart a background timer after it is confirmed.
    _finishEarly(finishWholeSession: true);
  }

  /// 供 macOS 灵动岛在工作台通过导航创建后执行暂停/继续。
  void handleTogglePause() {
    if (_phase != PomodoroPhase.focusing) return;
    if (_isPaused) {
      unawaited(_resumeFocus());
    } else {
      _pauseFocus();
    }
  }

  /// 保持灵动岛原有“结束当前专注轮次”的语义。
  void handleStopFocus() {
    _finishEarly();
  }

  @visibleForTesting
  static bool shouldStartBreakAfterCompletion({
    required bool isCountUp,
    required int currentCycle,
    required int cycles,
    required bool continueWithBreak,
  }) {
    return continueWithBreak && !isCountUp && currentCycle < cycles;
  }

  // 公开方法：供外部调用放弃专注
  void handleAbandonFocus() {
    _abandonFocus();
  }

  /// Opens the existing editor after an AI settings card is clicked.
  void showSettingsEntry({String? focusLabel}) =>
      _showSettingsDialog(focusLabel: focusLabel);

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final bool isIdle =
        _phase == PomodoroPhase.idle || _phase == PomodoroPhase.finished;
    final bool isFocusing = _phase == PomodoroPhase.focusing;
    final bool isRemoteWatching = _phase == PomodoroPhase.remoteWatching;
    final Color contentColor = Theme.of(context).colorScheme.onSurface;

    // PomodoroScreen already consumes the top safe area for its pinned glass
    // header. Applying the default top padding here again shifts the timer
    // and the active-state back button down by one status-bar inset.
    return SafeArea(
      top: false,
      bottom: false,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: _buildWorkbenchTransition,
        child: _initializing
            ? KeyedSubtree(
                key: const ValueKey('workbench_loading'),
                child: _buildSkeleton(),
              )
            : OrientationBuilder(
                key: const ValueKey('workbench_ready'),
                builder: (context, orientation) {
                  final isLandscape = orientation == Orientation.landscape;
                  _landscapeLayoutMounted = isLandscape;

                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isLandscape ? 32 : 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildHeader(
                          isIdle,
                          isFocusing,
                          isRemoteWatching,
                          isLandscape,
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: _buildWorkbenchTransition,
                            layoutBuilder: _buildLatestWorkbenchLayout,
                            child: isLandscape
                                ? _buildLandscapeLayout(
                                    isIdle,
                                    isFocusing,
                                    isRemoteWatching,
                                    contentColor,
                                  )
                                : _buildPortraitLayout(
                                    isIdle,
                                    isFocusing,
                                    isRemoteWatching,
                                    contentColor,
                                  ),
                          ),
                        ),
                        if (!isLandscape)
                          const SafeArea(
                            top: false,
                            child: SizedBox(height: 8),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
