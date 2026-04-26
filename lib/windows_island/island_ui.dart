import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:async';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'island_config.dart';
import 'island_state_stack.dart';
import '../storage_service.dart';
import '../services/course_service.dart';
import '../services/pomodoro_service.dart';
import '../services/system_control_service.dart';

// 导入鼠标事件类型
import 'package:flutter/gestures.dart' show PointerScrollEvent;

// Re-export IslandState for backward compatibility
export 'island_state_stack.dart' show IslandState;

class IslandUI extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final void Function(String action, [int? modifiedSecs, String? data])?
      onAction;
  final ValueNotifier<Map<String, dynamic>?>? payloadNotifier;
  final bool inLayoutDebugMode;

  const IslandUI({
    super.key,
    this.initialPayload,
    this.onAction,
    this.payloadNotifier,
    this.inLayoutDebugMode = false,
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
  late AnimationController _sizeController;
  late Animation<Size> _sizeAnimation;

  // ── 时间显示
  final ValueNotifier<String> _timeNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> _pauseTimeNotifier = ValueNotifier<String>('');
  Timer? _countdownTimer;
  int _remainingSecs = 0;
  bool _isCountdown = true;

  // ── 动画状态
  bool _transitioning = false;
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
  Timer? _mediaRefreshTimer;

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

  // ── 提醒相关
  Map<String, dynamic>? _reminderPopupData;
  String? _expandedReminderPart;
  Timer? _snoozeTimer;
  final Set<String> _acknowledgedReminderIds = {}; // 已确认的提醒ID

  // ── 窗口控制
  WindowController? _windowController;
  Size _currentWindowSize = const Size(120, 34);
  bool _isDragging = false;

  // ── 便捷 getter ─────────────────────────────────────────────────────────
  bool get _isFocusing => _stack.base == IslandState.focusing;

  Future<WindowController> _getController() async {
    _windowController ??= await WindowController.fromCurrentEngine();
    return _windowController!;
  }

  @override
  void initState() {
    super.initState();
    if (!widget.inLayoutDebugMode) {
      _getController();
    }

    _splitController = AnimationController(
      vsync: this,
      duration: IslandConfig.transitionDuration,
    );

    _sizeController = AnimationController(
      vsync: this,
      duration: IslandConfig.transitionDuration,
    );

    _sizeAnimation = Tween<Size>(
      begin: const Size(120, 34),
      end: const Size(120, 34),
    ).animate(CurvedAnimation(
      parent: _sizeController,
      curve: Curves.easeOutCubic,
    ));

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
    ]).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // 颜色闪烁动画
    _colorAnimation = ColorTween(
      begin: IslandConfig.focusColor,
      end: IslandConfig.warningColor,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    widget.payloadNotifier?.addListener(_onNotifierPayload);

    if (widget.initialPayload != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPayload(widget.initialPayload);
      });
    }

    // 启动 SMTC 媒体轮询
    SystemControlService.startMediaPolling(intervalMs: 3000);
    // 定时刷新 UI 上的媒体信息
    _mediaRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
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
    _resizeDebounce?.cancel();
    _timeNotifier.dispose();
    widget.payloadNotifier?.removeListener(_onNotifierPayload);
    _splitController.dispose();
    _sizeController.dispose();
    _pulseController.dispose(); // 清理脉冲动画控制器
    _mediaRefreshTimer?.cancel();
    SystemControlService.dispose();
    _windowController?.setWindowMethodHandler(null);
    super.dispose();
  }

  // ── 窗口大小控制 ─────────────────────────────────────────────────────────

  Timer? _resizeDebounce;

  Future<void> _resizeWindowOnce(Size targetSize) async {
    if (widget.inLayoutDebugMode) return;
    if (targetSize == _currentWindowSize) return;
    // 防抖：快速连续调用只执行最后一次
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 50), () async {
      if (!mounted) return;
      if (targetSize == _currentWindowSize) return;
      try {
        final ctrl = await _getController();
        if (!mounted) return;
        await ctrl.invokeMethod('setWindowSize', {
          'width': targetSize.width.toDouble(),
          'height': targetSize.height.toDouble(),
        });
        _currentWindowSize = targetSize;
      } catch (e) {
        debugPrint('[IslandUI] resize error: $e');
      }
    });
  }

  void _animateToState(IslandState nextState) {
    if (!mounted) return;

    final Size fromSize = _sizeAnimation.value;
    final Size toSize = _targetSizeFor(nextState);
    final int myVersion = ++_transitionVersion;

    _sizeAnimation =
        Tween<Size>(begin: fromSize, end: toSize).animate(CurvedAnimation(
      parent: _sizeController,
      curve: Curves.easeOutCubic,
    ));

    _resizeWindowOnce(toSize);

    _sizeController.forward(from: 0).then((_) {
      if (mounted && _transitionVersion == myVersion) {
        _transitioning = false;
      }
    });
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

  /// 完整状态映射
  IslandState _computeFullState(String stateStr) {
    switch (stateStr) {
      case 'focusing':
        return IslandState.focusing;
      case 'split_alert':
        return IslandState.splitAlert;
      case 'stacked_card':
        return IslandState.stackedCard;
      case 'finish_confirm':
        return IslandState.finishConfirm;
      case 'abandon_confirm':
        return IslandState.abandonConfirm;
      case 'finish_final':
        return IslandState.finishFinal;
      case 'reminder_popup':
        return IslandState.reminderPopup;
      case 'reminder_split':
        return IslandState.reminderSplit;
      case 'reminder_capsule':
        return IslandState.reminderCapsule;
      case 'copied_link':
        return IslandState.copiedLink;
      default:
        return _isFocusing ? IslandState.focusing : IslandState.idle;
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
        '[IslandUI] applyPayload: $stateStr, current: ${_stack.current}, isProtected: ${_stack.isProtected}');

    // ① 受保护状态：只更新数据，不切换状态
    if (_stack.isProtected) {
      debugPrint('[IslandUI] Blocked - state is protected');
      _ensureTimerRunning();
      return;
    }

    // ② 处理 copiedLink overlay
    final copiedLinkDataRaw = payload['copiedLinkData'];
    if (copiedLinkDataRaw != null && stateStr == 'copied_link') {
      final copiedLinkData =
          Map<String, dynamic>.from(copiedLinkDataRaw as Map);
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
        final pmm = (pSecs ~/ 60).toString().padLeft(2, '0');
        final pss = (pSecs % 60).toString().padLeft(2, '0');
        _pauseTimeNotifier.value = '$pmm:$pss';
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
      _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) _updateDisplayTime();
      });
      return;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final fd = _currentPayload?['focusData'] as Map?;
      final bool isPaused = fd?['isPaused'] ?? false;

      if (isPaused) {
        // 增加暂停计时
        final pStart = fd?['pauseStartMs'] ?? 0;
        if (pStart > 0) {
          final pSecs = (DateTime.now().millisecondsSinceEpoch - pStart) ~/ 1000;
          final pmm = (pSecs ~/ 60).toString().padLeft(2, '0');
          final pss = (pSecs % 60).toString().padLeft(2, '0');
          _pauseTimeNotifier.value = '$pmm:$pss';
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
    if (!_isFocusing) {
      final now = DateTime.now();
      _timeNotifier.value =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      return;
    }
    _timeNotifier.value =
        '${(_remainingSecs ~/ 60).toString().padLeft(2, '0')}:${(_remainingSecs % 60).toString().padLeft(2, '0')}';
  }

  // ── 尺寸配置 ─────────────────────────────────────────────────────────────

  Size _idleSizeForCard() {
    // 专注默认态：给字体留出更稳定的高度余量，避免不同 DPI 下溢出
    if (_isFocusing && !_isScrolledInFocus) {
      return const Size(112, 52);
    }
    if (_cards.isEmpty || _currentCardIndex >= _cards.length) {
      return const Size(120, 34);
    }
    final card = _cards[_currentCardIndex];
    final type = card['type'] as String;
    if (type == 'time') {
      return const Size(120, 34);
    }
    if (type == 'focusing') {
      return const Size(112, 52);
    }
    final title = card['title'] as String? ?? '';
    final subtitle = card['subtitle'] as String? ?? '';
    int maxLen = title.length;
    if (subtitle.length > maxLen) maxLen = subtitle.length;
    final textWidth = maxLen * 12.0;
    final width = (24 + 16 + 6 + textWidth).clamp(140.0, 300.0);
    final height = subtitle.isNotEmpty ? 48.0 : 34.0;
    return Size(width, height);
  }

  Size _targetSizeFor(IslandState s) {
    final hasSub =
        _reminderPopupData?['subtitle']?.toString().isNotEmpty ?? false;
    switch (s) {
      case IslandState.idle:
        return _idleSizeForCard();
      case IslandState.focusing:
        return const Size(112, 52);
      case IslandState.hoverWide:
        return const Size(380, 46);
      case IslandState.splitAlert:
        return const Size(300, 36);
      case IslandState.stackedCard:
        final hasSelected = _currentPayload?['selectedCard'] != null;
        return hasSelected ? const Size(250, 150) : const Size(280, 140);
      case IslandState.finishConfirm:
      case IslandState.abandonConfirm:
      case IslandState.finishFinal:
        return const Size(260, 130);
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
        return const Size(380, 60);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isTransparent = _stack.current == IslandState.reminderSplit;
    final isCard = _stack.current == IslandState.stackedCard ||
        _stack.current == IslandState.finishConfirm ||
        _stack.current == IslandState.abandonConfirm ||
        _stack.current == IslandState.finishFinal ||
        _stack.current == IslandState.reminderSplit;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedBuilder(
          animation: _sizeController,
          builder: (_, __) {
            final double borderRadius = isCard
                ? IslandConfig.cardRadius
                : IslandConfig.capsuleRadius;
            return Container(
              width: _sizeAnimation.value.width,
              height: _sizeAnimation.value.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 15,
                    spreadRadius: 1,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
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
                    child: AnimatedSwitcher(
                      duration: IslandConfig.switchDuration,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.92, end: 1.0)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      child: _buildContent(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_stack.current) {
      case IslandState.idle:
      case IslandState.focusing:
        return _buildIdle();
      case IslandState.hoverWide:
        return _buildHoverWide();
      case IslandState.stackedCard:
        return _buildStackedCard();
      case IslandState.splitAlert:
        return _buildSplitAlert();
      case IslandState.finishConfirm:
        return _buildConfirm('finish');
      case IslandState.abandonConfirm:
        return _buildConfirm('abandon');
      case IslandState.finishFinal:
        return _buildConfirm('final');
      case IslandState.copiedLink:
        return _buildCopiedLink();
      case IslandState.reminderPopup:
        return _buildReminderPopup();
      case IslandState.reminderSplit:
        return _buildReminderSplit();
      case IslandState.reminderCapsule:
        return _buildReminderCapsule();
      // 系统控制状态
      case IslandState.quickControls:
        return _buildQuickControls();
      case IslandState.musicPlayer:
        return _buildMusicPlayer();
      case IslandState.volumeControl:
        return _buildVolumeControl();
      case IslandState.brightnessControl:
        return _buildBrightnessControl();
      case IslandState.cardCarousel:
        return _buildCardCarousel();
    }
  }

  // ── SplitAlert ───────────────────────────────────────────────────────────

  Widget _buildSplitAlert() {
    return Container(
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: ValueListenableBuilder<String>(
                valueListenable: _timeNotifier,
                builder: (_, t, __) => Text(
                  t,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Idle 自动回位定时器（非专注模式用）
  Timer? _idleAutoReturnTimer;

  void _startIdleAutoReturnTimer() {
    _idleAutoReturnTimer?.cancel();
    _idleAutoReturnTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      // 专注模式：滚回计时器
      if (_isFocusing && _isScrolledInFocus) {
        setState(() {
          _isScrolledInFocus = false;
          _currentCardIndex = 0;
        });
        final newSize = _idleSizeForCard();
        _sizeAnimation = Tween<Size>(
          begin: newSize,
          end: newSize,
        ).animate(_sizeController);
        _resizeWindowOnce(newSize);
        return;
      }
      if (_stack.current != IslandState.idle) return;
      setState(() {
        _currentCardIndex = 0;
        _isScrolledInFocus = false;
      });
      final newSize = _idleSizeForCard();
      _sizeAnimation = Tween<Size>(
        begin: newSize,
        end: newSize,
      ).animate(_sizeController);
      _resizeWindowOnce(newSize);
    });
  }

  void _resetIdleAutoReturnTimer() {
    _idleAutoReturnTimer?.cancel();
    _startIdleAutoReturnTimer();
  }

  // ── Idle ─────────────────────────────────────────────────────────────────

  Widget _buildIdle() => GestureDetector(
        key: const ValueKey('idle'),
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_isFocusing && !_isScrolledInFocus) {
            // 专注状态默认 → 展开专注详情
            _stack.push(IslandState.stackedCard, data: _currentPayload);
            _animateToState(IslandState.stackedCard);
          } else if (_isFocusing && _isScrolledInFocus) {
            // 专注状态下滚轮切换后
            final card = _cards[_currentCardIndex];
            if (card['type'] == 'focusing') {
              // 专注状态卡 → 展开专注详情（完成/放弃）
              _isScrolledInFocus = false;
              _currentCardIndex = 0;
              _stack.push(IslandState.stackedCard, data: _currentPayload);
              _animateToState(IslandState.stackedCard);
            } else if (card['type'] == 'focus') {
              // 今日专注统计 → 展开统计详情
              final detailData = {...?_currentPayload, 'selectedCard': card};
              _currentPayload = detailData;
              _stack.push(IslandState.stackedCard, data: detailData);
              _animateToState(IslandState.stackedCard);
            } else {
              // 其他卡片 → 展开对应详情
              final detailData = {...?_currentPayload, 'selectedCard': card};
              _currentPayload = detailData;
              _stack.push(IslandState.stackedCard, data: detailData);
              _animateToState(IslandState.stackedCard);
            }
          } else if (_cards.isNotEmpty &&
              _currentCardIndex > 0 &&
              _cards[_currentCardIndex]['type'] != 'time') {
            // 非时间卡片：直接展开对应类型详情
            final card = _cards[_currentCardIndex];
            final detailData = {
              ...?_currentPayload,
              'selectedCard': card,
            };
            _currentPayload = detailData;
            _stack.push(IslandState.stackedCard, data: detailData);
            _animateToState(IslandState.stackedCard);
          } else {
            // 时间卡片：展开平铺视角
            _initCards();
            _stack.push(IslandState.cardCarousel, data: _currentPayload);
            _animateToState(IslandState.cardCarousel);
            _startCarouselAutoReturnTimer();
          }
        },
        onLongPress: () {
          _stack.push(IslandState.quickControls, data: _currentPayload);
          _animateToState(IslandState.quickControls);
          _startQuickControlsAutoReturnTimer();
        },
        onPanStart: (_) => _startDrag(),
        child: Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final delta = pointerSignal.scrollDelta.dy;
              if (delta != 0 && _cards.length > 1) {
                setState(() {
                  if (delta > 0) {
                    _currentCardIndex = (_currentCardIndex + 1) % _cards.length;
                  } else {
                    _currentCardIndex =
                        (_currentCardIndex - 1 + _cards.length) % _cards.length;
                  }
                  if (_isFocusing) _isScrolledInFocus = true;
                });
                final newSize = _idleSizeForCard();
                _sizeAnimation = Tween<Size>(
                  begin: newSize,
                  end: newSize,
                ).animate(_sizeController);
                _resizeWindowOnce(newSize);
                if (_isFocusing) {
                  _resetIdleAutoReturnTimer();
                } else if (_currentCardIndex > 0) {
                  _resetIdleAutoReturnTimer();
                }
              }
            }
          },
          child: Container(
            color: Colors.transparent,
            alignment: Alignment.center,
            child: (_isFocusing && !_isScrolledInFocus)
                ? _buildFocusTimerDisplay()
                : _buildIdleCardContent(),
          ),
        ),
      );

  // 专注计时器显示（从 _buildFocusing 提取，用于 idle 态下的专注显示）
  Widget _buildFocusTimerDisplay() {
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? '专注事项';

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _isPulsing ? _pulseAnimation.value : 1.0,
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            alignment: Alignment.center,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight <= 52;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!compact)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (fd?['isPaused'] == true) ...[
                            const Text(
                              '⏸️ ',
                              style: TextStyle(fontSize: 10),
                            ),
                          ],
                          Flexible(
                            child: ValueListenableBuilder<String>(
                              valueListenable: _pauseTimeNotifier,
                              builder: (context, pauseTime, _) {
                                return Text(
                                  fd?['isPaused'] == true ? '暂停中 $pauseTime' : title,
                                  style: TextStyle(
                                    color: _isPulsing
                                        ? _colorAnimation.value?.withValues(alpha: 0.7) ??
                                            Colors.white70
                                        : Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    if (!compact) const SizedBox(height: 1),
                    ValueListenableBuilder<String>(
                      valueListenable: _timeNotifier,
                      builder: (_, time, __) {
                        if (_isCountdown && _remainingSecs == 0 && !_isPulsing) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _triggerPomodoroAlert();
                          });
                        }
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            time,
                            style: TextStyle(
                              color: _isPulsing
                                  ? _colorAnimation.value ?? Colors.white
                                  : Colors.white,
                              fontSize: compact ? 16 : 16,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildIdleCardContent() {
    if (!_cardsLoaded || _cards.isEmpty) {
      if (!_cardsLoaded) {
        _initCards().then((_) {
          if (mounted) setState(() {});
        });
      }
      return ValueListenableBuilder<String>(
        valueListenable: _timeNotifier,
        builder: (_, time, __) => Text(
          time,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
      );
    }
    final card = _cards[_currentCardIndex];
    final type = card['type'] as String;
    final icon = card['icon'] as String;
    final title = card['title'] as String;
    final color = card['color'] as Color;

    // 时间卡片：显示当前时间
    if (type == 'time') {
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: Text(
          timeStr,
          key: ValueKey(_currentCardIndex),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
      );
    }

    // 专注状态卡片：显示专注计时器
    if (type == 'focusing') {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: Container(
          key: ValueKey(_currentCardIndex),
          alignment: Alignment.center,
          child: _buildFocusTimerDisplay(),
        ),
      );
    }

    // 数据卡片：显示内容
    final subtitle = card['subtitle'] as String;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, anim) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: Container(
        key: ValueKey(_currentCardIndex),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Focusing ─────────────────────────────────────────────────────────────

  Widget _buildFocusing() {
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? '专注事项';

    return GestureDetector(
      key: const ValueKey('focusing'),
      onTap: () {
        _stack.push(IslandState.stackedCard, data: _currentPayload);
        _animateToState(IslandState.stackedCard);
      },
      onPanStart: (_) => _startDrag(),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: _isPulsing ? _pulseAnimation.value : 1.0,
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              alignment: Alignment.center,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight <= 52;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!compact)
                        ValueListenableBuilder<String>(
                          valueListenable: _pauseTimeNotifier,
                          builder: (context, pauseTime, _) {
                            return Text(
                              fd?['isPaused'] == true ? '暂停中 $pauseTime' : title,
                              style: TextStyle(
                                color: _isPulsing
                                    ? _colorAnimation.value?.withValues(alpha: 0.7) ??
                                        Colors.white70
                                    : Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      if (!compact) const SizedBox(height: 1),
                      ValueListenableBuilder<String>(
                        valueListenable: _timeNotifier,
                        builder: (_, time, __) {
                          if (_isCountdown && _remainingSecs == 0 && !_isPulsing) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _triggerPomodoroAlert();
                            });
                          }

                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              time,
                              style: TextStyle(
                                color: _isPulsing
                                    ? _colorAnimation.value ?? Colors.white
                                    : Colors.white,
                                fontSize: compact ? 16 : 16,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  // 触发番茄钟结束强提醒
  void _triggerPomodoroAlert() {
    if (_isPulsing || !mounted) return;

    setState(() {
      _isPulsing = true;
    });

    // 启动脉冲动画，循环3次
    _pulseController.repeat(count: 3).then((_) {
      if (mounted) {
        setState(() {
          _isPulsing = false;
        });

        // 动画结束后自动展开番茄钟结束卡片
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _stack.current == IslandState.focusing) {
            _showPomodoroFinishedCard();
          }
        });
      }
    });
  }

  // 显示番茄钟结束卡片
  void _showPomodoroFinishedCard() {
    // 这里可以push一个新的状态来显示番茄钟结束卡片
    // 暂时使用现有的stackedCard状态
    _stack.push(IslandState.stackedCard, data: _currentPayload);
    _animateToState(IslandState.stackedCard);
  }

  // ── HoverWide ────────────────────────────────────────────────────────────

  Widget _buildHoverWide() {
    final p = _currentPayload;
    final dash = p?['dashboardData'] as Map?;
    final left =
        dash?['leftSlot']?.toString() ?? p?['topBarLeft']?.toString() ?? '';
    final right =
        dash?['rightSlot']?.toString() ?? p?['topBarRight']?.toString() ?? '';

    return GestureDetector(
      key: const ValueKey('hoverWide'),
      onTap: () {
        final restored = _stack.pop(IslandState.hoverWide);
        _animateToState(restored);
        if (_isFocusing) {
          _stack.push(IslandState.stackedCard, data: _currentPayload);
          _animateToState(IslandState.stackedCard);
        }
      },
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                left,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: _timeNotifier,
                builder: (_, t, __) => Text(
                  t,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                right,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── StackedCard ──────────────────────────────────────────────────────────

  Widget _buildStackedCard() {
    // 检查是否有选中的卡片类型（从 carousel 或 idle 点击进入）
    final selectedCard =
        _currentPayload?['selectedCard'] as Map<String, dynamic>?;
    if (selectedCard != null) {
      return _buildTypedDetail(selectedCard);
    }

    // 默认：专注详情
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? (_isCountdown ? '倒计时' : '自由专注');
    final tags = (fd?['tags'] as List?)?.join(' ') ?? '';
    final isLocal = fd?['syncMode']?.toString() != 'remote';

    return GestureDetector(
      key: const ValueKey('stackedCard'),
      onTap: () {
        _currentPayload?.remove('selectedCard');
        final restored = _stack.pop(IslandState.stackedCard);
        _animateToState(restored);
      },
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: _pauseTimeNotifier,
              builder: (context, pauseTime, _) {
                return ValueListenableBuilder<String>(
                  valueListenable: _timeNotifier,
                  builder: (_, t, __) => Text(
                    fd?['isPaused'] == true
                        ? '暂停中 $pauseTime | $t'
                        : '$t | $title',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                );
              },
            ),
            if (tags.isNotEmpty)
              Text(
                tags,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 16),
            if (!isLocal)
              _btn('远端计时中，无法更改', Colors.white.withValues(alpha: 0.1), () {})
            else
              Row(
                children: [
                  Expanded(
                    child: _btn('完成', IslandConfig.successColor, () {
                      _stack.push(IslandState.finishConfirm,
                          data: _currentPayload);
                      _animateToState(IslandState.finishConfirm);
                    }),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _btn('放弃', IslandConfig.dangerColor, () {
                      _stack.push(IslandState.abandonConfirm,
                          data: _currentPayload);
                      _animateToState(IslandState.abandonConfirm);
                    }),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // 卡片类型详情（待办/倒计时/课程/专注统计）
  Widget _buildTypedDetail(Map<String, dynamic> card) {
    final type = card['type'] as String;
    final icon = card['icon'] as String;
    final title = card['title'] as String;
    final subtitle = card['subtitle'] as String;
    final color = card['color'] as Color;

    String header;
    String detail;
    switch (type) {
      case 'todo':
        header = '📝 待办事项';
        detail = subtitle.isNotEmpty ? '到期时间: $subtitle' : '无截止日期';
        break;
      case 'countdown':
        header = '⏰ 倒计时';
        detail = subtitle.isNotEmpty ? subtitle : '目标日期已设置';
        break;
      case 'course':
        final dateLabel = card['dateLabel']?.toString() ?? '';
        final roomName = card['roomName']?.toString() ?? '';
        final startTime = card['startTime']?.toString() ?? '';
        header = '📚 课程';
        String info = dateLabel;
        if (startTime.isNotEmpty) info += ' $startTime';
        if (roomName.isNotEmpty) info += ' $roomName';
        detail = info.isNotEmpty ? info : '暂无详细信息';
        break;
      case 'focus':
        header = '🎯 专注统计';
        detail = subtitle.isNotEmpty ? subtitle : '暂无专注记录';
        break;
      default:
        header = '$icon $title';
        detail = subtitle;
    }

    return GestureDetector(
      key: const ValueKey('typedDetail'),
      onTap: () {
        _currentPayload?.remove('selectedCard');
        final restored = _stack.pop(IslandState.stackedCard);
        _animateToState(restored);
      },
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              header,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _btn('关闭', color.withValues(alpha: 0.8), () {
              _currentPayload?.remove('selectedCard');
              final restored = _stack.pop(IslandState.stackedCard);
              _animateToState(restored);
            }),
          ],
        ),
      ),
    );
  }

  // ── Confirm (finish / abandon / final) ───────────────────────────────────

  Widget _buildConfirm(String mode) {
    String text = mode == 'finish'
        ? '确认完成?'
        : mode == 'abandon'
            ? '确认放弃?'
            : '专注完成';
    String ok = mode == 'final' ? '好的' : '确认';
    String cancel = '手滑了';
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? '专注内容';
    final isReverse = mode == 'abandon';

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$title | ${_timeNotifier.value}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          if (mode == 'final')
            // FinishFinal: 好的 → clearToIdle
            _btn(ok, IslandConfig.successColor, () {
              _stack.clearToIdle();
              _animateToState(IslandState.idle);
            })
          else
            Row(
              children: [
                if (!isReverse) ...[
                  // FinishConfirm: 确认 → 发 action，清栈，push finishFinal
                  Expanded(
                    child: _btn(ok, IslandConfig.successColor, () {
                      widget.onAction?.call('finish', _remainingSecs);
                      _stack.clearToIdle();
                      _stack.push(IslandState.finishFinal);
                      _animateToState(IslandState.finishFinal);
                    }),
                  ),
                  const SizedBox(width: 12),
                  // FinishConfirm: 手滑了 → pop，回到 stackedCard
                  Expanded(
                    child: _btn(cancel, IslandConfig.dangerColor, () {
                      final restored = _stack.pop(IslandState.finishConfirm);
                      _animateToState(restored);
                    }),
                  ),
                ] else ...[
                  // AbandonConfirm: 手滑了 → pop，回到 stackedCard
                  Expanded(
                    child: _btn(cancel, IslandConfig.successColor, () {
                      final restored = _stack.pop(IslandState.abandonConfirm);
                      _animateToState(restored);
                    }),
                  ),
                  const SizedBox(width: 12),
                  // AbandonConfirm: 确认 → 发 action，清栈到 idle
                  Expanded(
                    child: _btn(ok, IslandConfig.dangerColor, () {
                      widget.onAction?.call('abandon', 0);
                      _stack.clearToIdle();
                      _animateToState(IslandState.idle);
                    }),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // ── CopiedLink（双层灵动岛设计）──────────────────────────────────────────

  Widget _buildCopiedLink() {
    final d = _currentPayload?['copiedLinkData'] as Map?;
    if (d == null) return const SizedBox.shrink();
    final url = d['url']?.toString() ?? '';
    final display = d['displayUrl']?.toString() ??
        (url.length > 25 ? '${url.substring(0, 25)}...' : url);

    return Column(
      key: const ValueKey('copiedLink'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 主岛：居中显示
        Center(child: _buildMainIslandContent()),
        const SizedBox(height: 4),
        // 副岛：链接提示
        GestureDetector(
          onPanStart: (_) => _startDrag(),
          child: Container(
            width: 340,
            height: 46,
            decoration: BoxDecoration(
              color: IslandConfig.bgColor,
              borderRadius: BorderRadius.circular(IslandConfig.capsuleRadius),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.5),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('🔗', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已复制: $display',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _miniBtn('打开', IslandConfig.successColor, () {
                  widget.onAction?.call('open_link', 0, url);
                  _autoDismissTimer?.cancel();
                  final restored = _stack.pop(IslandState.copiedLink);
                  _animateToState(restored);
                }),
                const SizedBox(width: 6),
                _miniBtn('✕', Colors.white.withValues(alpha: 0.2), () {
                  _autoDismissTimer?.cancel();
                  final restored = _stack.pop(IslandState.copiedLink);
                  _animateToState(restored);
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 构建主岛内容（时钟或专注状态）
  Widget _buildMainIslandContent() {
    if (_isFocusing) {
      final fd = _currentPayload?['focusData'] as Map?;
      final title = fd?['title']?.toString() ?? '专注事项';
      return Container(
        width: 100,
        height: 46,
        decoration: BoxDecoration(
          color: IslandConfig.bgColor,
          borderRadius: BorderRadius.circular(IslandConfig.capsuleRadius),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            ValueListenableBuilder<String>(
              valueListenable: _timeNotifier,
              builder: (_, time, __) => Text(
                time,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        width: 120,
        height: 34,
        decoration: BoxDecoration(
          color: IslandConfig.bgColor,
          borderRadius: BorderRadius.circular(IslandConfig.capsuleRadius),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        alignment: Alignment.center,
        child: ValueListenableBuilder<String>(
          valueListenable: _timeNotifier,
          builder: (_, time, __) => Text(
            time,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ),
      );
    }
  }

  // ── ReminderPopup ────────────────────────────────────────────────────────

  Widget _buildReminderPopup() {
    final d = _reminderPopupData;
    if (d == null) return const SizedBox.shrink();

    final isSpecial = _isSpecialTodo(d);
    final specialType = d['specialType']?.toString();
    final type = d['type']?.toString() ?? 'todo';

    final IconData iconData;
    final Color iconColor;
    final String iconStr;
    final String label;

    if (isSpecial) {
      iconData = _getSpecialTodoIcon(specialType);
      iconColor = _getSpecialTodoColor(specialType);
      iconStr = '';
      label = _getSpecialTodoLabel(specialType);
    } else {
      iconData = Icons.task_alt;
      iconColor = IslandConfig.warningColor;
      iconStr = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
      label = type == 'course' ? '课程' : (type == 'todo' ? '待办' : '倒计时');
    }

    final mins = d['minutesUntil'] as int? ?? 0;
    final isEnd = d['isEnding'] as bool? ?? false;
    final status = isEnd ? '还有 $mins 分钟结束' : '还有 $mins 分钟开始';
    final itemId = d['itemId']?.toString();
    final subtitle = (d['subtitle'] ?? '').toString();

    return GestureDetector(
      key: const ValueKey('reminderPopup'),
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: icon + title
            Row(
              children: [
                if (isSpecial)
                  Icon(iconData, color: iconColor, size: 20)
                else
                  Text(iconStr, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$label：${d['title']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // Subtitle (remark/code) - highlighted for special todos
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: isSpecial ? Colors.white : Colors.white70,
                  fontSize: isSpecial ? 13 : 11,
                  fontWeight: isSpecial ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // 好的 → 发 action，标记已确认，pop reminderPopup
                Expanded(
                  child: _btn('好的', IslandConfig.successColor, () {
                    debugPrint(
                        '[IslandUI] reminder_ok clicked (popup), itemId=$itemId');
                    widget.onAction?.call('reminder_ok', 0);
                    if (itemId != null) {
                      _acknowledgedReminderIds.add(itemId);
                    }
                    _reminderPopupData = null;
                    _stack.clearToIdle();
                    _animateToState(IslandState.idle);
                  }),
                ),
                const SizedBox(width: 12),
                // 稍后提醒 → 发 action，标记已确认，pop 回 reminderCapsule
                Expanded(
                  child: _btn('稍后提醒', IslandConfig.warningColor, () {
                    debugPrint('[IslandUI] remind_later clicked (popup)');
                    widget.onAction?.call('remind_later', 0);
                    if (itemId != null) {
                      _acknowledgedReminderIds.add(itemId);
                    }
                    _reminderPopupData = null;
                    _stack.clearToIdle();
                    _animateToState(IslandState.idle);
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── ReminderSplit ────────────────────────────────────────────────────────

  Widget _buildReminderSplit() {
    final d = _reminderPopupData;
    if (d == null) {
      // 提醒数据丢失时回退到专注显示，避免完全透明无响应
      return _buildFocusTimerDisplay();
    }

    final isSpecial = _isSpecialTodo(d);
    final specialType = d['specialType']?.toString();
    final type = d['type']?.toString() ?? 'todo';
    final mins = '${d['minutesUntil'] as int? ?? 0}min';
    final expanded = _expandedReminderPart;

    final Widget reminderCapsule;
    if (isSpecial) {
      final iconData = _getSpecialTodoIcon(specialType);
      final color = _getSpecialTodoColor(specialType);
      reminderCapsule = _capsuleWithWidget(
        Icon(iconData, color: Colors.white, size: 12),
        '${d['title']} $mins',
        color,
      );
    } else {
      final icon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
      reminderCapsule =
          _capsule(icon, '${d['title']} $mins', IslandConfig.warningColor);
    }

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final delta = pointerSignal.scrollDelta.dy;
              setState(() {
                if (delta > 0) {
                  _remainingSecs = (_remainingSecs - 60).clamp(0, 999999);
                } else {
                  _remainingSecs += 60;
                }
              });
              _updateDisplayTime();
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final newExpanded = expanded == 'focusing' ? null : 'focusing';
              setState(() {
                _expandedReminderPart = newExpanded;
              });
              Future.microtask(
                  () => _animateToState(IslandState.reminderSplit));
            },
            child: _capsule('🎯', _timeNotifier.value, IslandConfig.focusColor),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final newExpanded = expanded == 'reminder' ? null : 'reminder';
            setState(() {
              _expandedReminderPart = newExpanded;
            });
            Future.microtask(() => _animateToState(IslandState.reminderSplit));
          },
          child: reminderCapsule,
        ),
      ],
    );

    if (expanded == null) {
      return KeyedSubtree(
          key: const ValueKey('reminderSplit'), child: Center(child: row));
    }

    final card =
        expanded == 'focusing' ? _expandedFocusing() : _expandedReminder();
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
            top: 0, left: 0, right: 0, height: 46, child: Center(child: row)),
        Positioned(top: 54, left: 8, right: 8, child: card),
      ],
    );
  }

  Widget _capsule(String icon, String text, Color color) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 60),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  /// Capsule variant that accepts a Widget icon (e.g. Material Icons)
  Widget _capsuleWithWidget(Widget iconWidget, String text, Color color) =>
      Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 60),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  Widget _expandedFocusing() {
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? (_isCountdown ? '倒计时' : '自由专注');
    return Container(
      width: 260,
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IslandConfig.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: _timeNotifier,
            builder: (_, t, __) => Text(
              '$t | $title',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // 完成 → push finishConfirm
              Expanded(
                child: _btn('完成', IslandConfig.successColor, () {
                  _stack.push(IslandState.finishConfirm, data: _currentPayload);
                  _animateToState(IslandState.finishConfirm);
                }),
              ),
              const SizedBox(width: 8),
              // 放弃 → push abandonConfirm
              Expanded(
                child: _btn('放弃', IslandConfig.dangerColor, () {
                  _stack.push(IslandState.abandonConfirm,
                      data: _currentPayload);
                  _animateToState(IslandState.abandonConfirm);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _expandedReminder() {
    final d = _reminderPopupData;
    if (d == null) return const SizedBox.shrink();

    final isSpecial = _isSpecialTodo(d);
    final specialType = d['specialType']?.toString();
    final type = d['type']?.toString() ?? 'todo';

    final IconData iconData;
    final Color iconColor;
    final String label;

    if (isSpecial) {
      iconData = _getSpecialTodoIcon(specialType);
      iconColor = _getSpecialTodoColor(specialType);
      label = _getSpecialTodoLabel(specialType);
    } else {
      iconData = Icons.task_alt;
      iconColor = Colors.transparent;
      label = type == 'course' ? '课程' : (type == 'todo' ? '待办' : '倒计时');
    }

    final iconStr = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final mins = d['minutesUntil'] as int? ?? 0;
    final isEnd = d['isEnding'] as bool? ?? false;
    final status = isEnd ? '还有 $mins 分钟结束' : '还有 $mins 分钟开始';
    final itemId = d['itemId']?.toString();
    final subtitle = (d['subtitle'] ?? '').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IslandConfig.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: icon + title
          Row(
            children: [
              if (isSpecial)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(iconData, color: iconColor, size: 20),
                )
              else
                Text(iconStr, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSpecial ? '$label：${d['title']}' : '$label：${d['title']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: isSpecial ? Colors.white : Colors.white70,
                fontSize: isSpecial ? 13 : 11,
                fontWeight: isSpecial ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(status,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            children: [
              // 好的 → 发 action，标记已确认，恢复 focusing
              Expanded(
                child: _btn('好的', IslandConfig.successColor, () {
                  debugPrint('[IslandUI] reminder_ok clicked, itemId=$itemId');
                  widget.onAction?.call('reminder_ok', 0);
                  if (itemId != null) {
                    _acknowledgedReminderIds.add(itemId);
                  }
                  _reminderPopupData = null;
                  _expandedReminderPart = null;
                  _stack.replaceTop(IslandState.focusing,
                      data: _currentPayload);
                  _animateToState(IslandState.focusing);
                }),
              ),
              const SizedBox(width: 8),
              // 稍后提醒 → 发 action，收起但保留双胶囊
              Expanded(
                child: _btn('稍后提醒', IslandConfig.warningColor, () {
                  debugPrint('[IslandUI] remind_later clicked');
                  widget.onAction?.call('remind_later', 0);
                  if (itemId != null) {
                    _acknowledgedReminderIds.add(itemId);
                  }
                  setState(() => _expandedReminderPart = null);
                  _animateToState(IslandState.reminderSplit);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── ReminderCapsule ──────────────────────────────────────────────────────

  Widget _buildReminderCapsule() {
    final d = _reminderPopupData;
    if (d == null) return const SizedBox.shrink();

    final isSpecial = _isSpecialTodo(d);
    final specialType = d['specialType']?.toString();
    final type = d['type']?.toString() ?? 'todo';

    final Widget capsuleWidget;
    if (isSpecial) {
      final iconData = _getSpecialTodoIcon(specialType);
      final color = _getSpecialTodoColor(specialType);
      capsuleWidget = _capsuleWithWidget(
        Icon(iconData, color: Colors.white, size: 12),
        '${d['title']} ${d['minutesUntil']}min',
        color,
      );
    } else {
      final icon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
      capsuleWidget = _capsule(icon, '${d['title']} ${d['minutesUntil']}min',
          IslandConfig.warningColor);
    }

    return GestureDetector(
      key: const ValueKey('reminderCapsule'),
      onPanStart: (_) => _startDrag(),
      // 点击胶囊 → push reminderPopup
      onTap: () {
        _stack.push(IslandState.reminderPopup, data: _currentPayload);
        _animateToState(IslandState.reminderPopup);
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(8),
        child: capsuleWidget,
      ),
    );
  }

  // ── 特殊待办工具方法 ─────────────────────────────────────────────────────

  /// Get Material icon for special todo type (matches Android res/drawable icons)
  static IconData _getSpecialTodoIcon(String? specialType) {
    switch (specialType) {
      case 'delivery':
        return Icons.local_shipping; // matches local_shipping.xml
      case 'food':
        return Icons.shopping_bag; // matches shopping_bag.xml
      case 'cafe':
        return Icons.local_cafe; // matches local_cafe.xml
      case 'restaurant':
        return Icons.restaurant; // matches restaurant.xml
      default:
        return Icons.task_alt;
    }
  }

  /// Get color for special todo type (matches Android drawable fillColor)
  static Color _getSpecialTodoColor(String? specialType) {
    switch (specialType) {
      case 'delivery':
        return const Color(0xFFFF8142); // orange from local_shipping.xml
      case 'food':
        return const Color(0xFFFFAF22); // yellow from shopping_bag.xml
      case 'cafe':
        return const Color(0xFF6CCE25); // green from local_cafe.xml
      case 'restaurant':
        return const Color(0xFFF5726E); // red from restaurant.xml
      default:
        return IslandConfig.warningColor;
    }
  }

  /// Get display label for special todo type
  static String _getSpecialTodoLabel(String? specialType) {
    switch (specialType) {
      case 'delivery':
        return '快递';
      case 'food':
        return '外卖';
      case 'cafe':
        return '饮品';
      case 'restaurant':
        return '餐饮';
      default:
        return '待办';
    }
  }

  /// Check if reminder data represents a special todo
  static bool _isSpecialTodo(Map<String, dynamic>? data) {
    return data?['specialType'] != null &&
        data!['specialType'].toString().isNotEmpty;
  }

  // ── 通用按钮 ─────────────────────────────────────────────────────────────

  Widget _miniBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      );

  Widget _btn(String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      );

  void _startDrag() async {
    if (widget.inLayoutDebugMode) return;
    _isDragging = true;
    try {
      (await _getController()).invokeMethod('startDragging');
      Future.delayed(const Duration(milliseconds: 100), () {
        _isDragging = false;
      });
    } catch (_) {
      _isDragging = false;
    }
  }

  // ── 卡片轮播相关方法 ────────────────────────────────────────────────────

  // 初始化卡片列表
  Future<void> _initCards() async {
    if (_cardsLoaded) return;

    // 保存专注卡片，避免被 clear 清掉
    final focusingCard =
        _cards.where((c) => c['type'] == 'focusing').firstOrNull;

    _cards.clear();
    _currentCardIndex = 0;

    // index 0: 时间卡片（始终在首位）
    _cards.add({
      'type': 'time',
      'icon': '🕐',
      'title': '当前时间',
      'subtitle': '',
      'color': Colors.white54,
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final username = prefs.getString('current_login_user') ?? '';

      if (username.isEmpty) {
        _addDefaultCard();
        _cardsLoaded = true;
        return;
      }

      final now = DateTime.now();

      // 添加待办事项卡片
      try {
        final todos = await StorageService.getTodos(username);
        if (!mounted) return;
        final activeTodos =
            todos.where((todo) => !todo.isDeleted && !todo.isDone).toList();
        activeTodos.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        if (activeTodos.isNotEmpty) {
          final todo = activeTodos.first;
          String subtitle = '';
          if (todo.dueDate != null) {
            final diff = todo.dueDate!.difference(now);
            if (diff.inDays > 0) {
              subtitle = '${diff.inDays}天后到期';
            } else if (diff.inHours > 0) {
              subtitle = '${diff.inHours}小时后到期';
            } else if (diff.inMinutes > 0) {
              subtitle = '${diff.inMinutes}分钟后到期';
            } else {
              subtitle = '已到期';
            }
          }
          _cards.add({
            'type': 'todo',
            'icon': '📝',
            'title': todo.title,
            'subtitle': subtitle,
            'color': IslandConfig.focusColor,
          });
        }
      } catch (e) {
        debugPrint('[IslandUI] 读取待办失败: $e');
      }

      // 添加倒计时卡片
      try {
        final countdowns = await StorageService.getCountdowns(username);
        if (!mounted) return;
        final activeCountdowns = countdowns
            .where((cd) => !cd.isDeleted && cd.targetDate.isAfter(now))
            .toList();
        activeCountdowns.sort((a, b) => a.targetDate.compareTo(b.targetDate));
        if (activeCountdowns.isNotEmpty) {
          final countdown = activeCountdowns.first;
          final diff = countdown.targetDate.difference(now);
          String subtitle;
          if (diff.inDays > 0) {
            subtitle = '还有${diff.inDays}天';
          } else if (diff.inHours > 0) {
            subtitle = '还有${diff.inHours}小时';
          } else if (diff.inMinutes > 0) {
            subtitle = '还有${diff.inMinutes}分钟';
          } else {
            subtitle = '时间到';
          }
          _cards.add({
            'type': 'countdown',
            'icon': '⏰',
            'title': countdown.title,
            'subtitle': subtitle,
            'color': IslandConfig.dangerColor,
          });
        }
      } catch (e) {
        debugPrint('[IslandUI] 读取倒计时失败: $e');
      }

      // 添加课程卡片
      try {
        final dashboardCourses = await CourseService.getDashboardCourses(username);
        if (!mounted) return;
        final courses = dashboardCourses['courses'] as List? ?? [];
        if (courses.isNotEmpty) {
          final isToday = dashboardCourses['title'] == '今日课程';
          // 过滤已结束的今日课程
          final validCourses = isToday
              ? courses.where((c) {
                  final endHour = c.endTime ~/ 100;
                  final endMin = c.endTime % 100;
                  final courseEnd =
                      DateTime(now.year, now.month, now.day, endHour, endMin);
                  return now.isBefore(courseEnd);
                }).toList()
              : courses;
          if (validCourses.isNotEmpty) {
            final nextCourse = validCourses.first;
            final courseDateStr = nextCourse.date;
            final todayStr =
                '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
            String dateLabel;
            if (courseDateStr == todayStr) {
              dateLabel = nextCourse.formattedStartTime;
            } else {
              try {
                final courseDate = DateTime.parse(courseDateStr);
                final today = DateTime(now.year, now.month, now.day);
                final diff =
                    DateTime(courseDate.year, courseDate.month, courseDate.day)
                        .difference(today)
                        .inDays;
                if (diff == 1) {
                  dateLabel = '明天';
                } else if (diff == 2) {
                  dateLabel = '后天';
                } else {
                  dateLabel = '$diff天后';
                }
              } catch (_) {
                dateLabel = dashboardCourses['title']?.toString() ?? '课程';
              }
            }
            _cards.add({
              'type': 'course',
              'icon': '📚',
              'title': nextCourse.courseName,
              'subtitle': dateLabel,
              'color': IslandConfig.warningColor,
              'dateLabel': dateLabel,
              'fullDate': courseDateStr,
              'roomName': nextCourse.roomName,
              'startTime': nextCourse.formattedStartTime,
            });
          } // validCourses.isNotEmpty
        } // courses.isNotEmpty
      } catch (e) {
        debugPrint('[IslandUI] 读取课程失败: $e');
      }

      // 添加专注时长卡片
      try {
        final records = await PomodoroService.getRecords();
        if (!mounted) return;
        final todayStart =
            DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
        int todayFocusSeconds = 0;
        for (final r in records) {
          if (r.startTime >= todayStart &&
              r.status == PomodoroRecordStatus.completed) {
            todayFocusSeconds += r.actualDuration ?? 0;
          }
        }
        final hours = todayFocusSeconds ~/ 3600;
        final minutes = (todayFocusSeconds % 3600) ~/ 60;
        final timeStr = todayFocusSeconds > 0
            ? (hours > 0 ? '$hours时$minutes分' : '$minutes分钟')
            : '0分钟';
        _cards.add({
          'type': 'focus',
          'icon': '🎯',
          'title': '今日专注',
          'subtitle': timeStr,
          'color': IslandConfig.focusColor,
        });
      } catch (e) {
        debugPrint('[IslandUI] 读取专注时长失败: $e');
      }
    } catch (e) {
      debugPrint('[IslandUI] 初始化卡片失败: $e');
    }

    if (_cards.isEmpty) {
      _addDefaultCard();
    }

    // 恢复专注卡片
    if (focusingCard != null) {
      _cards.add(focusingCard);
    }

    _cardsLoaded = true;
  }

  void _addDefaultCard() {
    _cards.add({
      'type': 'default',
      'icon': '📋',
      'title': '暂无内容',
      'subtitle': '点击添加待办或课程',
      'color': Colors.white54,
    });
  }

  // 启动自动返回定时器
  void _startCarouselAutoReturnTimer() {
    _carouselAutoReturnTimer?.cancel();
    _carouselAutoReturnTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _stack.current == IslandState.cardCarousel) {
        _stack.pop(IslandState.cardCarousel);
        _animateToState(IslandState.idle);
      }
    });
  }

  // 构建卡片并排平铺
  Widget _buildCardCarousel() {
    if (_cards.isEmpty) {
      return const Center(
        child: Text(
          '暂无卡片',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }

    return GestureDetector(
      key: const ValueKey('cardCarousel'),
      onTap: () {
        _currentPayload?.remove('selectedCard');
        _stack.pop(IslandState.cardCarousel);
        _animateToState(IslandState.idle);
      },
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: _cards.where((c) => c['type'] != 'focusing').map((card) {
            final type = card['type'] as String;
            final icon = card['icon'] as String;
            final title = card['title'] as String;
            final subtitle = card['subtitle'] as String;
            final color = card['color'] as Color;

            Widget cardContent;
            VoidCallback onTap;

            if (type == 'time') {
              cardContent = Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 14)),
                  ValueListenableBuilder<String>(
                    valueListenable: _timeNotifier,
                    builder: (_, time, __) => Text(
                      time,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              );
              onTap = () {
                _currentPayload?.remove('selectedCard');
                _stack.pop(IslandState.cardCarousel);
                _animateToState(IslandState.idle);
              };
            } else {
              cardContent = Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$icon $title',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 9,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              );
              onTap = () {
                final detailData = {
                  ...?_currentPayload,
                  'selectedCard': card,
                };
                _currentPayload = detailData;
                _stack.pop(IslandState.cardCarousel);
                _stack.push(IslandState.stackedCard, data: detailData);
                _animateToState(IslandState.stackedCard);
              };
            }

            return Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: cardContent,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── 系统控制UI ─────────────────────────────────────────────────────────

  // 快速控制面板（3 按钮横排：音量 / 亮度 / 音乐）
  Widget _buildQuickControls() {
    return GestureDetector(
      key: const ValueKey('quickControls'),
      onTap: () {
        _cancelAllSystemControlTimers();
        _stack.pop(IslandState.quickControls);
        _animateToState(_stack.current);
      },
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _quickControlBtn(
              '🔊',
              '音量',
              IslandConfig.focusColor,
              () {
                SystemControlService.initVolume();
                _stack.push(IslandState.volumeControl, data: _currentPayload);
                _animateToState(IslandState.volumeControl);
                _startSystemControlAutoReturnTimer();
              },
            ),
            _quickControlBtn(
              '☀️',
              '亮度',
              IslandConfig.warningColor,
              () {
                _stack.push(IslandState.brightnessControl,
                    data: _currentPayload);
                _animateToState(IslandState.brightnessControl);
                _startSystemControlAutoReturnTimer();
              },
            ),
            _quickControlBtn(
              '🎵',
              '音乐',
              IslandConfig.focusColor,
              () {
                _stack.push(IslandState.musicPlayer, data: _currentPayload);
                _animateToState(IslandState.musicPlayer);
                _startSystemControlAutoReturnTimer();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickControlBtn(
          String icon, String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 80,
          height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );

  // ── 音乐播放器 ─────────────────────────────────────────────────────────

  // 音乐播放器（包含歌词显示）
  Widget _buildMusicPlayer() {
    final musicData = _currentPayload?['musicData'] as Map?;
    final hasMusic = musicData != null && musicData.isNotEmpty;

    // 从 SMTC 获取系统媒体信息
    final smtc = SystemControlService.getMediaInfo();
    final smtcHasMusic = !smtc.isEmpty;

    // 优先使用 payload 中的数据，其次使用 SMTC 数据
    final title =
        musicData?['title']?.toString() ?? (smtcHasMusic ? smtc.title : '');
    final artist =
        musicData?['artist']?.toString() ?? (smtcHasMusic ? smtc.artist : '');
    final isPlaying = musicData?['isPlaying'] as bool? ??
        (smtc.status == PlaybackStatus.playing);
    final currentTime = musicData?['currentTime']?.toString() ?? '0:00';
    final totalTime = musicData?['totalTime']?.toString() ?? '0:00';
    final lyrics = musicData?['lyrics']?.toString() ?? '';
    final currentLyricIndex = musicData?['currentLyricIndex'] as int? ?? 0;
    final shuffleOn = musicData?['shuffle'] as bool? ?? false;
    final repeatMode = musicData?['repeat']?.toString() ?? 'off';

    final showContent = hasMusic || smtcHasMusic;

    return GestureDetector(
      key: const ValueKey('musicPlayer'),
      onTap: () {
        _systemControlAutoReturnTimer?.cancel();
        _stack.pop(IslandState.musicPlayer);
        _stack.push(IslandState.quickControls, data: _currentPayload);
        _animateToState(IslandState.quickControls);
        _startQuickControlsAutoReturnTimer();
      },
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(14),
        child: showContent
            ? _buildMusicPlayerContent(title, artist, isPlaying, currentTime,
                totalTime, lyrics, currentLyricIndex, shuffleOn, repeatMode)
            : _buildMusicEmptyState(),
      ),
    );
  }

  Widget _buildMusicEmptyState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🎵', style: TextStyle(fontSize: 28)),
        const SizedBox(height: 8),
        const Text(
          '暂无播放中的音乐',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '打开音乐播放器后将自动显示',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 12),
        _miniBtn('返回', Colors.white.withValues(alpha: 0.15), () {
          _systemControlAutoReturnTimer?.cancel();
          _quickControlsAutoReturnTimer?.cancel();
          _sliderDebounce?.cancel();
          _quickControlsAutoReturnTimer?.cancel();
          _quickControlsAutoReturnTimer?.cancel();
          _stack.pop(IslandState.musicPlayer);
          _stack.push(IslandState.quickControls, data: _currentPayload);
          _animateToState(IslandState.quickControls);
        }),
      ],
    );
  }

  Widget _buildMusicPlayerContent(
    String title,
    String artist,
    bool isPlaying,
    String currentTime,
    String totalTime,
    String lyrics,
    int currentLyricIndex,
    bool shuffleOn,
    String repeatMode,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: IslandConfig.focusColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.music_note,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isNotEmpty ? title : '未知歌曲',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist.isNotEmpty ? artist : '未知艺术家',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        currentTime,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onPanStart: (details) {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            final pos =
                                box.globalToLocal(details.localPosition);
                            final fraction =
                                (pos.dx / box.size.width).clamp(0.0, 1.0);
                            widget.onAction
                                ?.call('music_seek', (fraction * 1000).round());
                          },
                          child: Container(
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor:
                                  _calculateProgress(currentTime, totalTime),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: IslandConfig.focusColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        totalTime,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 控制按钮行
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _miniBtn(
              shuffleOn ? '🔀' : '➡️',
              shuffleOn
                  ? IslandConfig.focusColor.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1),
              () => widget.onAction?.call('music_shuffle'),
            ),
            const SizedBox(width: 10),
            _miniBtn('⏮', Colors.white.withValues(alpha: 0.15), () {
              widget.onAction?.call('music_prev');
              _resetSystemControlAutoReturnTimer();
            }),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                widget.onAction?.call('music_toggle');
                _resetSystemControlAutoReturnTimer();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: IslandConfig.focusColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _miniBtn('⏭', Colors.white.withValues(alpha: 0.15), () {
              widget.onAction?.call('music_next');
              _resetSystemControlAutoReturnTimer();
            }),
            const SizedBox(width: 10),
            _miniBtn(
              repeatMode == 'one'
                  ? '🔂'
                  : repeatMode == 'all'
                      ? '🔁'
                      : '➡️',
              repeatMode != 'off'
                  ? IslandConfig.focusColor.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1),
              () => widget.onAction?.call('music_repeat'),
            ),
          ],
        ),
        // 歌词显示区域
        if (lyrics.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  '🎵 歌词',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                ..._buildLyricsLines(lyrics, currentLyricIndex),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // 计算播放进度
  double _calculateProgress(String current, String total) {
    try {
      final currentParts = current.split(':');
      final totalParts = total.split(':');

      if (currentParts.length == 2 && totalParts.length == 2) {
        final currentSeconds =
            int.parse(currentParts[0]) * 60 + int.parse(currentParts[1]);
        final totalSeconds =
            int.parse(totalParts[0]) * 60 + int.parse(totalParts[1]);

        if (totalSeconds > 0) {
          return (currentSeconds / totalSeconds).clamp(0.0, 1.0);
        }
      }
    } catch (_) {}
    return 0.0;
  }

  // 构建歌词行
  List<Widget> _buildLyricsLines(String lyrics, int currentIndex) {
    final lines = lyrics.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length && i < 3; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        final isCurrentLine = i == currentIndex;
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              style: TextStyle(
                color: isCurrentLine ? Colors.white : Colors.white70,
                fontSize: isCurrentLine ? 12 : 11,
                fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }

    return widgets;
  }

  // ── 音量控制 ─────────────────────────────────────────────────────────

  Widget _buildVolumeControl() {
    final currentVolume = SystemControlService.getVolumeSync();
    final isMuted = currentVolume <= 0.01;
    final volumePercent = (currentVolume * 100).round();

    String volumeIcon;
    if (isMuted) {
      volumeIcon = '🔇';
    } else if (volumePercent < 30) {
      volumeIcon = '🔈';
    } else if (volumePercent < 70) {
      volumeIcon = '🔉';
    } else {
      volumeIcon = '🔊';
    }

    return GestureDetector(
      key: const ValueKey('volumeControl'),
      onTap: () {
        _systemControlAutoReturnTimer?.cancel();
        _stack.pop(IslandState.volumeControl);
        _stack.push(IslandState.quickControls, data: _currentPayload);
        _animateToState(IslandState.quickControls);
        _startQuickControlsAutoReturnTimer();
      },
      onPanStart: (_) => _startDrag(),
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            final delta = pointerSignal.scrollDelta.dy;
            final current = SystemControlService.getVolumeSync();
            final newVol = (current - delta * 0.003).clamp(0.0, 1.0);
            SystemControlService.setVolume(newVol);
            setState(() {});
            _resetSystemControlAutoReturnTimer();
          }
        },
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(volumeIcon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '音量',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Text(
                      '$volumePercent%',
                      key: ValueKey(volumePercent),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // 静音/取消静音
                  _miniBtn(
                    isMuted ? '🔇' : '🔈',
                    isMuted
                        ? IslandConfig.dangerColor.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.1),
                    () {
                      if (isMuted) {
                        SystemControlService.setVolume(_savedVolumeBeforeMute);
                      } else {
                        _savedVolumeBeforeMute = currentVolume;
                        SystemControlService.setVolume(0);
                      }
                      setState(() {});
                      _resetSystemControlAutoReturnTimer();
                    },
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: IslandConfig.focusColor,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                        thumbColor: Colors.white,
                        overlayColor: IslandConfig.focusColor.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: currentVolume,
                        onChanged: (value) {
                          SystemControlService.setVolume(value);
                          setState(() {});
                          _resetSystemControlAutoReturnTimer();
                        },
                        onChangeEnd: (value) {
                          SystemControlService.commitVolume(value);
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  // 最大音量
                  _miniBtn('🔊', Colors.white.withValues(alpha: 0.1), () {
                    SystemControlService.setVolume(1.0);
                    setState(() {});
                    _resetSystemControlAutoReturnTimer();
                  }),
                ],
              ),
              // 快捷音量档位
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [0, 25, 50, 75, 100].map((level) {
                  final isActive = (volumePercent - level).abs() < 13;
                  return GestureDetector(
                    onTap: () {
                      SystemControlService.setVolume(level / 100.0);
                      setState(() {});
                      _resetSystemControlAutoReturnTimer();
                    },
                    child: Container(
                      width: 40,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isActive
                            ? IslandConfig.focusColor.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isActive
                              ? IslandConfig.focusColor.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$level',
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 亮度控制 ─────────────────────────────────────────────────────────

  Widget _buildBrightnessControl() {
    final currentBrightness = SystemControlService.getBrightness();
    final brightnessPercent = (currentBrightness * 100).round();

    String brightnessIcon;
    if (brightnessPercent < 20) {
      brightnessIcon = '🌙';
    } else if (brightnessPercent < 60) {
      brightnessIcon = '⛅';
    } else {
      brightnessIcon = '☀️';
    }

    return GestureDetector(
      key: const ValueKey('brightnessControl'),
      onTap: () {
        _systemControlAutoReturnTimer?.cancel();
        _stack.pop(IslandState.brightnessControl);
        _stack.push(IslandState.quickControls, data: _currentPayload);
        _animateToState(IslandState.quickControls);
        _startQuickControlsAutoReturnTimer();
      },
      onPanStart: (_) => _startDrag(),
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            final delta = pointerSignal.scrollDelta.dy;
            final current = SystemControlService.getBrightness();
            final newBri = (current - delta * 0.003).clamp(0.0, 1.0);
            SystemControlService.setBrightness(newBri);
            setState(() {});
            _resetSystemControlAutoReturnTimer();
          }
        },
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(brightnessIcon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '亮度',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Text(
                      '$brightnessPercent%',
                      key: ValueKey(brightnessPercent),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // 最低亮度
                  _miniBtn('🌙', Colors.white.withValues(alpha: 0.1), () {
                    SystemControlService.setBrightness(0.05);
                    setState(() {});
                    _resetSystemControlAutoReturnTimer();
                  }),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: IslandConfig.warningColor,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                        thumbColor: Colors.white,
                        overlayColor:
                            IslandConfig.warningColor.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: currentBrightness,
                        onChanged: (value) {
                          SystemControlService.setBrightness(value);
                          setState(() {});
                          _resetSystemControlAutoReturnTimer();
                        },
                      ),
                    ),
                  ),
                  // 最高亮度
                  _miniBtn('☀️', Colors.white.withValues(alpha: 0.1), () {
                    SystemControlService.setBrightness(1.0);
                    setState(() {});
                    _resetSystemControlAutoReturnTimer();
                  }),
                ],
              ),
              // 快捷亮度档位
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [5, 25, 50, 75, 100].map((level) {
                  final isActive = (brightnessPercent - level).abs() < 13;
                  return GestureDetector(
                    onTap: () {
                      SystemControlService.setBrightness(level / 100.0);
                      setState(() {});
                      _resetSystemControlAutoReturnTimer();
                    },
                    child: Container(
                      width: 40,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isActive
                            ? IslandConfig.warningColor.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isActive
                              ? IslandConfig.warningColor.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$level',
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
