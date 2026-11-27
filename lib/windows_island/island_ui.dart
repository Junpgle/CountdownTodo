import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'dart:async';

import 'island_config.dart';
import 'island_state_stack.dart';
import 'island_win32.dart';
import '../utils/app_image_filters.dart';
import '../utils/app_platform.dart';
import '../services/system_control_service.dart';
import '../utils/time_utils.dart';

// 导入鼠标事件类型
import 'package:flutter/gestures.dart' show PointerScrollEvent;

// Re-export IslandState for backward compatibility
export 'island_state_stack.dart' show IslandState;

part 'parts/island_ui_idle_and_cards.dart';
part 'parts/island_ui_reminders.dart';
part 'parts/island_ui_carousel_and_controls.dart';

const double _maxNativeResizeWidth = 480.0;
const double _maxNativeResizeHeight = 340.0;

class IslandUI extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final void Function(String action, [int? modifiedSecs, String? data])?
  onAction;
  final ValueNotifier<Map<String, dynamic>?>? payloadNotifier;
  final bool inLayoutDebugMode;
  final VoidCallback? onStartDrag;

  const IslandUI({
    super.key,
    this.initialPayload,
    this.onAction,
    this.payloadNotifier,
    this.inLayoutDebugMode = false,
    this.onStartDrag,
  });

  @override
  State<IslandUI> createState() => _IslandUIState();
}

class _IslandUIState extends State<IslandUI> with TickerProviderStateMixin {
  // ── 唯一的状态源：栈
  final IslandStateStack _stack = IslandStateStack();

  // ── 当前 payload
  Map<String, dynamic>? _currentPayload;

  // ── 自动消失定时器
  Timer? _autoDismissTimer;

  // ── 动画控制器
  late AnimationController _splitController;
  late Animation<double> _splitProgress;
  late Animation<double> _splitRowOpacity;
  late Animation<double> _splitCardTop;
  late Animation<double> _splitCardScale;
  late AnimationController _sizeController;
  late Animation<Size> _sizeAnimation;
  late Animation<double> _radiusAnimation;

  // ── 时间显示
  final ValueNotifier<String> _timeNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> _clockTimeNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> _pauseTimeNotifier = ValueNotifier<String>('');
  Timer? _countdownTimer;
  int _remainingSecs = 0;
  bool _isCountdown = true;

  // ── 动画状态
  int _transitionVersion = 0;

  // ── 强提醒动画
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<Color?> _colorAnimation;
  bool _isPulsing = false;

  // ── 卡片轮播相关
  Timer? _carouselAutoReturnTimer;
  int _currentCardIndex = 0;
  final List<Map<String, dynamic>> _cards = [];
  bool _cardsLoaded = false;
  bool _isScrolledInFocus = false; // 专注状态下是否已滚轮切换到其他卡片

  // ── 系统控制状态
  double _savedVolumeBeforeMute = 0.75;
  Timer? _sliderDebounce;

  // ── 系统控制超时返回
  Timer? _systemControlAutoReturnTimer;
  Timer? _quickControlsAutoReturnTimer;
  bool _mediaPollingStarted = false;

  // 启动系统控制自动返回定时器（子控制 → 快速面板）
  void _startSystemControlAutoReturnTimer() {
    _systemControlAutoReturnTimer?.cancel();
    _systemControlAutoReturnTimer = Timer(const Duration(seconds: 10), () {
      if (mounted &&
          (_stack.current == IslandState.musicPlayer ||
              _stack.current == IslandState.volumeControl ||
              _stack.current == IslandState.brightnessControl)) {
        _stack.pop(_stack.current);
        _animateToState(IslandState.quickControls);
        _startQuickControlsAutoReturnTimer();
      }
    });
  }

  void _resetSystemControlAutoReturnTimer() {
    _systemControlAutoReturnTimer?.cancel();
    _startSystemControlAutoReturnTimer();
  }

  // 启动快速控制面板自动返回定时器（3秒无操作 → 回上一状态）
  void _startQuickControlsAutoReturnTimer() {
    _quickControlsAutoReturnTimer?.cancel();
    _quickControlsAutoReturnTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _stack.current == IslandState.quickControls) {
        _cancelAllSystemControlTimers();
        _stack.pop(IslandState.quickControls);
        _animateToState(_stack.current);
      }
    });
  }

  void _cancelAllSystemControlTimers() {
    _systemControlAutoReturnTimer?.cancel();
    _quickControlsAutoReturnTimer?.cancel();
  }

  // ── Payload 防抖
  Timer? _payloadDebounce;

  // ── Idle 自动回位定时器（非专注模式用）
  Timer? _idleAutoReturnTimer;

  // ── 提醒相关
  Map<String, dynamic>? _reminderPopupData;
  String? _expandedReminderPart;
  Timer? _snoozeTimer;
  final Set<String> _acknowledgedReminderIds = {}; // 已确认的提醒ID
  bool _confirmActionSent = false;

  // ── 窗口控制
  Size _currentWindowSize = const Size(100, 34);
  // ── 便捷 getter ─────────────────────────────────────────────────────────
  bool get _isFocusing => _stack.base == IslandState.focusing;

  @override
  void initState() {
    super.initState();

    _splitController = AnimationController(
      vsync: this,
      duration: IslandConfig.transitionDuration,
    );
    _splitProgress = _splitController.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    _splitRowOpacity = Tween<double>(
      begin: 0.75,
      end: 1.0,
    ).animate(_splitProgress);
    _splitCardTop = Tween<double>(
      begin: 66.0,
      end: 54.0,
    ).animate(_splitProgress);
    _splitCardScale = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(_splitProgress);

    _sizeController = AnimationController(
      vsync: this,
      duration: IslandConfig.transitionDuration,
    );

    _sizeAnimation = Tween<Size>(
      begin: const Size(100, 34),
      end: const Size(100, 34),
    ).animate(_sizeController.drive(CurveTween(curve: Curves.easeOutCubic)));
    _radiusAnimation = AlwaysStoppedAnimation<double>(
      IslandConfig.capsuleRadius,
    );

    // 初始化脉冲动画控制器
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // 脉冲动画：缩放效果
    _pulseAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 25),
    ]).animate(_pulseController.drive(CurveTween(curve: Curves.easeInOut)));

    // 颜色闪烁动画
    _colorAnimation = ColorTween(
      begin: IslandConfig.focusColor,
      end: IslandConfig.warningColor,
    ).animate(_pulseController.drive(CurveTween(curve: Curves.easeInOut)));

    widget.payloadNotifier?.addListener(_onNotifierPayload);

    if (widget.initialPayload != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPayload(widget.initialPayload);
      });
    }
  }

  @override
  void dispose() {
    _payloadDebounce?.cancel();
    _countdownTimer?.cancel();
    _autoDismissTimer?.cancel();
    _snoozeTimer?.cancel();
    _idleAutoReturnTimer?.cancel();
    _carouselAutoReturnTimer?.cancel();
    _systemControlAutoReturnTimer?.cancel();
    _quickControlsAutoReturnTimer?.cancel();
    _sliderDebounce?.cancel();
    _resizeDebounce?.cancel();
    _timeNotifier.dispose();
    _clockTimeNotifier.dispose();
    _pauseTimeNotifier.dispose();
    widget.payloadNotifier?.removeListener(_onNotifierPayload);
    _splitController.dispose();
    _sizeController.dispose();
    _pulseController.dispose(); // 清理脉冲动画控制器
    _stopMediaPolling();
    SystemControlService.dispose();
    super.dispose();
  }

  // ── 窗口大小控制 ─────────────────────────────────────────────────────────

  Timer? _resizeDebounce;

  void _resizeWindowOnce(Size targetSize) {
    if (widget.inLayoutDebugMode) return;
    if (targetSize == _currentWindowSize) return;
    if (targetSize.width > _maxNativeResizeWidth ||
        targetSize.height > _maxNativeResizeHeight) {
      debugPrint(
        '[IslandUI] skip native resize for oversized target: $targetSize',
      );
      return;
    }
    // 防抖：快速连续调用只执行最后一次
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      if (targetSize == _currentWindowSize) return;
      try {
        resizeCurrentWindow(
          targetSize.width.round(),
          targetSize.height.round(),
        );
        _currentWindowSize = targetSize;
      } catch (e) {
        debugPrint('[IslandUI] resize error: $e');
      }
    });
  }

  void _animateToState(IslandState nextState) {
    if (!mounted) return;

    if (nextState == IslandState.musicPlayer) {
      _ensureMediaPollingStarted();
    } else {
      _stopMediaPolling();
    }

    final Size toSize = _targetSizeFor(nextState);
    _animateSurfaceTo(toSize, _radiusFor(nextState));

    if (nextState == IslandState.reminderSplit) {
      if (_expandedReminderPart == null) {
        _splitController.reverse();
      } else {
        _splitController.forward(from: 0);
      }
    }
  }

  void _animateSizeTo(Size toSize) {
    _animateSurfaceTo(toSize, _radiusFor(_stack.current));
  }

  void _animateSurfaceTo(Size toSize, double endRadius) {
    final beginSize = _sizeAnimation.value;
    final beginRadius = _radiusAnimation.value;
    final version = ++_transitionVersion;
    final growsWindow =
        toSize.width > _currentWindowSize.width ||
        toSize.height > _currentWindowSize.height;

    _resizeDebounce?.cancel();
    _sizeController.stop();
    _sizeController.reset();
    _sizeAnimation = Tween<Size>(
      begin: beginSize,
      end: toSize,
    ).animate(_sizeController.drive(CurveTween(curve: Curves.easeOutCubic)));
    _radiusAnimation = Tween<double>(
      begin: beginRadius,
      end: endRadius,
    ).animate(_sizeController.drive(CurveTween(curve: Curves.easeOutCubic)));

    if (growsWindow) {
      _resizeWindowOnce(toSize);
    }

    if (mounted) {
      setState(() {});
    }
    _sizeController.forward().whenComplete(() {
      if (!mounted || version != _transitionVersion) return;
      if (!growsWindow) {
        _resizeWindowOnce(toSize);
      }
      setState(() {});
    });
  }

  void _ensureMediaPollingStarted() {
    if (_mediaPollingStarted) return;
    _mediaPollingStarted = true;
    SystemControlService.startMediaPolling(intervalMs: 3000);
  }

  void _stopMediaPolling() {
    if (!_mediaPollingStarted) return;
    _mediaPollingStarted = false;
    SystemControlService.stopMediaPolling();
  }

  // ── 状态计算 ─────────────────────────────────────────────────────────────

  /// 基础状态映射（只有 idle 和 focusing 作为栈底）
  IslandState _computeBaseState(String stateStr) {
    switch (stateStr) {
      case 'focusing':
      case 'reminder_split': // 专注中的提醒，底层仍是 focusing
        return IslandState.focusing;
      default:
        return IslandState.idle;
    }
  }

  // ── Payload 处理 ─────────────────────────────────────────────────────────

  void _onNotifierPayload() {
    _payloadDebounce?.cancel();
    _payloadDebounce = Timer(IslandConfig.payloadDebounce, () {
      if (mounted) _applyPayload(widget.payloadNotifier?.value);
    });
  }

  void _applyPayload(Map<String, dynamic>? payload) {
    if (payload == null || !mounted) return;
    _currentPayload = payload;
    _cardsLoaded = false; // payload 变化时刷新卡片数据

    final stateStr = payload['state']?.toString() ?? 'idle';
    final nextBase = _computeBaseState(stateStr);

    debugPrint(
      '[IslandUI] applyPayload: $stateStr, current: ${_stack.current}, isProtected: ${_stack.isProtected}',
    );

    // ① 受保护状态：只更新数据，不切换状态
    if (_stack.isProtected) {
      debugPrint('[IslandUI] Blocked - state is protected');
      _ensureTimerRunning();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (stateStr == 'focusing') {
      _confirmActionSent = false;
    }

    // ② 处理 copiedLink overlay
    final copiedLinkDataRaw = payload['copiedLinkData'];
    if (copiedLinkDataRaw != null && stateStr == 'copied_link') {
      final copiedLinkData = Map<String, dynamic>.from(
        copiedLinkDataRaw as Map,
      );
      _pushWithAutoDismiss(
        IslandState.copiedLink,
        data: {...payload, 'copiedLinkData': copiedLinkData},
        duration: IslandConfig.copiedLinkDismissDuration,
      );
      return;
    }

    // ③ 处理 reminderPopup（非专注状态的提醒弹窗）
    if (stateStr == 'reminder_popup') {
      final rd = payload['reminderPopupData'];
      if (rd != null) _reminderPopupData = Map<String, dynamic>.from(rd as Map);
      _stack.push(IslandState.reminderPopup, data: payload);
      _animateToState(IslandState.reminderPopup);
      return;
    }

    // ④ 处理 reminderSplit（专注中收到提醒）
    if (stateStr == 'reminder_split') {
      final rd = payload['reminderPopupData'];
      if (rd != null) {
        final rdMap = Map<String, dynamic>.from(rd as Map);
        final itemId = rdMap['itemId']?.toString();
        // 检查是否已确认过此提醒
        if (itemId != null && _acknowledgedReminderIds.contains(itemId)) {
          debugPrint('[IslandUI] Skipping acknowledged reminder: $itemId');
          return;
        }
        _reminderPopupData = rdMap;
      }
      final isNewReminder = _stack.current != IslandState.reminderSplit;
      _stack.replaceTop(IslandState.reminderSplit, data: payload);
      _updateFocusTimer(payload);
      if (isNewReminder) {
        // 首次出现：强提醒，自动展开提醒卡片
        _expandedReminderPart = 'reminder';
      }
      _animateToState(IslandState.reminderSplit);
      return;
    }

    // ⑤ 处理 reminderCapsule（非专注状态的提醒胶囊）
    if (stateStr == 'reminder_capsule') {
      final rd = payload['reminderPopupData'];
      if (rd != null) {
        final rdMap = Map<String, dynamic>.from(rd as Map);
        final itemId = rdMap['itemId']?.toString();
        // 检查是否已确认过此提醒
        if (itemId != null && _acknowledgedReminderIds.contains(itemId)) {
          debugPrint('[IslandUI] Skipping acknowledged reminder: $itemId');
          return;
        }
        _reminderPopupData = rdMap;
      }
      _stack.replaceBase(IslandState.reminderCapsule, data: payload);
      _animateToState(IslandState.reminderCapsule);
      return;
    }

    // ⑥ 处理 snooze_reminder
    if (stateStr == 'snooze_reminder') {
      final mins = payload['snoozeMinutes'] as int? ?? 5;
      if (_reminderPopupData != null) {
        _reminderPopupData = {
          ..._reminderPopupData!,
          'minutesUntil': mins,
          'acknowledged': false,
        };
        if (_isFocusing) {
          // 专注中：强提醒，展开提醒卡片
          _expandedReminderPart = 'reminder';
          _stack.replaceTop(IslandState.reminderSplit, data: payload);
          _animateToState(IslandState.reminderSplit);
        } else {
          // 非专注：直接弹出 reminderPopup
          _stack.push(IslandState.reminderPopup, data: payload);
          _animateToState(IslandState.reminderPopup);
        }
      }
      return;
    }

    // ⑦ 更新基础状态（idle <-> focusing）
    if (nextBase != _stack.base) {
      if (nextBase == IslandState.idle) {
        _isScrolledInFocus = false;
        // 移除专注状态卡片
        _cards.removeWhere((c) => c['type'] == 'focusing');
        if (_currentCardIndex >= _cards.length) _currentCardIndex = 0;
      }
      if (nextBase == IslandState.focusing) {
        _initCards();
        // 追加专注状态卡片到末尾
        if (!_cards.any((c) => c['type'] == 'focusing')) {
          _cards.add({
            'type': 'focusing',
            'icon': '⏱️',
            'title': _isCountdown ? '倒计时' : '专注中',
            'subtitle': '',
            'color': IslandConfig.focusColor,
          });
        }
      }
      _stack.replaceBase(nextBase, data: payload);
      _animateToState(nextBase);
    }

    // ⑧ 更新专注计时器
    _updateFocusTimer(payload);

    _ensureTimerRunning();
    if (mounted) {
      setState(() {});
    }
  }

  void _updateFocusTimer(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final fd = payload['focusData'] as Map?;
    if (fd == null) return;

    _isCountdown = fd['isCountdown'] ?? true;
    final endMs = (fd['endMs'] as num?)?.toInt() ?? 0;
    final isPaused = fd['isPaused'] as bool? ?? false;
    final pauseStartMs = (fd['pauseStartMs'] as num?)?.toInt() ?? 0;
    final isCountUp = !_isCountdown;

    if (endMs > 0) {
      if (isPaused) {
        if (isCountUp) {
          _remainingSecs = ((pauseStartMs - endMs) / 1000).round();
        } else {
          _remainingSecs = ((endMs - pauseStartMs) / 1000).round();
        }
        // 同步更新暂停显示
        final pSecs =
            (DateTime.now().millisecondsSinceEpoch - pauseStartMs) ~/ 1000;
        _pauseTimeNotifier.value = formatTimerMMSS(pSecs);
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (isCountUp) {
          _remainingSecs = ((now - endMs) / 1000).round();
        } else {
          _remainingSecs = ((endMs - now) / 1000).round();
        }
      }
      _remainingSecs = _remainingSecs.clamp(0, 999999);
    }
    _updateDisplayTime();
  }

  // ── 自动消失 ─────────────────────────────────────────────────────────────

  void _pushWithAutoDismiss(
    IslandState state, {
    Map<String, dynamic>? data,
    required Duration duration,
  }) {
    _autoDismissTimer?.cancel();
    _stack.push(state, data: data);
    _animateToState(state);

    _autoDismissTimer = Timer(duration, () {
      if (mounted && _stack.current == state) {
        final restored = _stack.pop(state);
        _animateToState(restored);
      }
    });
  }

  // ── Hover 处理（已移除）───────────────────────────────────────────────────

  // void _onHoverEnter() { ... }
  // void _onHoverExit() { ... }
  // void _doShrink() { ... }

  // ── 时间处理 ─────────────────────────────────────────────────────────────

  void _ensureTimerRunning() {
    _countdownTimer?.cancel();
    if (!_isFocusing) {
      _updateDisplayTime();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) _updateDisplayTime();
      });
      return;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateClockTime();
      final fd = _currentPayload?['focusData'] as Map?;
      final bool isPaused = fd?['isPaused'] ?? false;

      if (isPaused) {
        // 增加暂停计时
        final pStart = fd?['pauseStartMs'] ?? 0;
        if (pStart > 0) {
          final pSecs =
              (DateTime.now().millisecondsSinceEpoch - pStart) ~/ 1000;
          _pauseTimeNotifier.value = formatTimerMMSS(pSecs);
        }
        return;
      }

      if (_isCountdown) {
        if (_remainingSecs > 0) _remainingSecs--;
      } else {
        _remainingSecs++;
      }
      _updateDisplayTime();
    });
  }

  void _updateDisplayTime() {
    _updateClockTime();
    if (!_isFocusing) {
      _timeNotifier.value = _clockTimeNotifier.value;
      return;
    }
    _timeNotifier.value = formatTimerMMSS(_remainingSecs);
  }

  void _updateClockTime() {
    final now = DateTime.now();
    _clockTimeNotifier.value = AppTimeFormats.clock(now);
  }

  // ── 尺寸配置 ─────────────────────────────────────────────────────────────

  Size _idleSizeForCard() {
    // 专注默认态：给字体留出更稳定的高度余量，避免不同 DPI 下溢出
    if (_isFocusing && !_isScrolledInFocus) {
      return const Size(90, 40);
    }
    if (_cards.isEmpty || _currentCardIndex >= _cards.length) {
      return const Size(100, 34);
    }
    final card = _cards[_currentCardIndex];
    final type = card['type'] as String;
    if (type == 'time') {
      return const Size(100, 34);
    }
    if (type == 'focusing') {
      return const Size(132, 54);
    }
    final title = card['title'] as String? ?? '';
    final subtitle = card['subtitle'] as String? ?? '';
    final maxLen = title.length > subtitle.length
        ? title.length
        : subtitle.length;
    final textWidth = maxLen.clamp(0, 14) * 10.0;
    final maxWidth = switch (type) {
      'course' => 190.0,
      'countdown' => 180.0,
      'todo' => 200.0,
      _ => 180.0,
    };
    final width = (46 + textWidth).clamp(100.0, maxWidth);
    final height = subtitle.isNotEmpty ? 52.0 : 40.0;
    return Size(width, height);
  }

  Size _cardCarouselSize() {
    final visibleCount = _cards.where((c) => c['type'] != 'focusing').length;
    final count = visibleCount <= 0 ? 1 : visibleCount;
    const horizontalPadding = 16.0;
    const cardWidth = 76.0;
    const gap = 6.0;
    final width = (horizontalPadding + count * cardWidth + (count - 1) * gap)
        .clamp(220.0, _maxNativeResizeWidth);
    return Size(width, 96);
  }

  Size _stackedCardSize() {
    if (_currentPayload?['selectedCard'] != null) {
      return const Size(260, 150);
    }
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? '';
    final tags = fd?['tags'] as List?;
    final hasTags = tags != null && tags.isNotEmpty;
    final hasNote = fd?['note']?.toString().trim().isNotEmpty == true;
    final textLen = title.isEmpty ? 8 : title.length.clamp(8, 16);
    final width = (112 + textLen * 8.0).clamp(180.0, 240.0);
    double height = hasTags ? 112.0 : 98.0;
    if (hasNote) height += 28;
    return Size(width, height);
  }

  Size _targetSizeFor(IslandState s) {
    final hasSub =
        _reminderPopupData?['subtitle']?.toString().isNotEmpty ?? false;
    switch (s) {
      case IslandState.idle:
        return _idleSizeForCard();
      case IslandState.focusing:
        return const Size(120, 64);
      case IslandState.hoverWide:
        return const Size(380, 56);
      case IslandState.splitAlert:
        return const Size(300, 36);
      case IslandState.stackedCard:
        return _stackedCardSize();
      case IslandState.finishConfirm:
      case IslandState.abandonConfirm:
      case IslandState.finishFinal:
        return const Size(270, 146);
      case IslandState.reminderPopup:
        return Size(320, hasSub ? 180 : 150);
      case IslandState.reminderSplit:
        if (_expandedReminderPart != null) {
          // 展开态：根据展开的是哪侧决定高度
          final hasSub =
              _reminderPopupData?['subtitle']?.toString().isNotEmpty ?? false;
          return Size(320, hasSub ? 340 : 300);
        }
        return const Size(480, 46);
      case IslandState.reminderCapsule:
        return const Size(160, 46);
      case IslandState.copiedLink:
        final mainHeight = _isFocusing ? 46.0 : 34.0;
        return Size(340, mainHeight + 4 + 46 + 8);
      // 系统控制状态
      case IslandState.quickControls:
        return const Size(264, 66);
      case IslandState.musicPlayer:
        return const Size(360, 200);
      case IslandState.volumeControl:
        return const Size(320, 140);
      case IslandState.brightnessControl:
        return const Size(320, 140);
      case IslandState.cardCarousel:
        return _cardCarouselSize();
    }
  }

  double _radiusFor(IslandState s) {
    switch (s) {
      case IslandState.stackedCard:
      case IslandState.finishConfirm:
      case IslandState.abandonConfirm:
      case IslandState.finishFinal:
      case IslandState.reminderPopup:
      case IslandState.reminderSplit:
      case IslandState.musicPlayer:
      case IslandState.volumeControl:
      case IslandState.brightnessControl:
      case IslandState.cardCarousel:
        return IslandConfig.cardRadius;
      case IslandState.idle:
      case IslandState.focusing:
      case IslandState.hoverWide:
      case IslandState.splitAlert:
      case IslandState.reminderCapsule:
      case IslandState.copiedLink:
      case IslandState.quickControls:
        return IslandConfig.capsuleRadius;
    }
  }

  String _contentKeyForCurrentState() {
    final selectedCard = _currentPayload?['selectedCard'];
    final selectedType = selectedCard is Map ? selectedCard['type'] : null;
    return '${_stack.current.name}:${selectedType ?? ''}';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final isTransparent = _stack.current == IslandState.reminderSplit;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedBuilder(
          animation: _sizeController,
          child: AnimatedSwitcher(
            duration: IslandConfig.switchDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.center,
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, anim) {
              final scale = Tween<double>(
                begin: IslandConfig.switchScaleBegin,
                end: IslandConfig.switchScaleEnd,
              ).animate(anim);
              return AnimatedBuilder(
                animation: anim,
                child: child,
                builder: (context, child) {
                  if (anim.value <= 0.001) {
                    return const SizedBox.shrink();
                  }
                  if (anim.value >= 0.999) {
                    return child!;
                  }
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: scale, child: child),
                  );
                },
              );
            },
            child: KeyedSubtree(
              key: ValueKey(_contentKeyForCurrentState()),
              child: _buildContent(),
            ),
          ),
          builder: (_, child) {
            final double borderRadius = _radiusAnimation.value;
            final surface = Container(
              decoration: BoxDecoration(
                color: isTransparent
                    ? Colors.transparent
                    : IslandConfig.bgColor.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(borderRadius),
                border: isTransparent
                    ? null
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
              ),
              clipBehavior: Clip.antiAlias,
              child: child!,
            );
            final glassSurface = AppPlatform.isWindows
                ? surface
                : BackdropFilter(filter: AppImageFilters.blur6, child: surface);

            return Container(
              width: _sizeAnimation.value.width,
              height: _sizeAnimation.value.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: RepaintBoundary(child: glassSurface),
              ),
            );
          },
        ),
      ),
    );
  }
}
