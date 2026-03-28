import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:async';
import 'dart:ui';

enum IslandState {
  idle,
  focusing,
  hoverWide,
  splitAlert,
  stackedCard,
  finishConfirm,
  abandonConfirm,
  finishFinal,
  reminderPopup,
  reminderSplit,
  reminderCapsule,
  copiedLink,
}

class IslandUI extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final void Function(String action, [int? modifiedSecs])? onAction;
  final ValueNotifier<Map<String, dynamic>?>? payloadNotifier;

  const IslandUI({
    super.key,
    this.initialPayload,
    this.onAction,
    this.payloadNotifier,
  });

  @override
  State<IslandUI> createState() => _IslandUIState();
}

class _IslandUIState extends State<IslandUI> with TickerProviderStateMixin {
  IslandState _state = IslandState.idle;
  IslandState? _savedStateBeforeHover;
  Map<String, dynamic>? _currentPayload;
  bool _isFocusing = false;

  late AnimationController _splitController;
  late AnimationController _sizeController;
  late Animation<Size> _sizeAnimation;

  final ValueNotifier<String> _timeNotifier = ValueNotifier<String>('');

  Timer? _countdownTimer;
  int _remainingSecs = 0;
  bool _isCountdown = true;

  bool _transitioning = false;
  int _transitionVersion = 0;
  Timer? _hoverDebounce;
  Timer? _payloadDebounce;
  Timer? _minStayTimer;
  bool _isHovered = false;
  bool _canShrink = true; // 防止刚展开就收缩

  // 提醒弹出相关状态
  Map<String, dynamic>? _reminderPopupData;
  IslandState? _savedStateBeforeReminder;
  String? _expandedReminderPart;

  // 复制链接相关状态
  Map<String, dynamic>? _copiedLinkData;
  IslandState? _savedStateBeforeCopiedLink;
  Timer? _copiedLinkTimer;

  WindowController? _windowController;

  // ══════════════════════════════════════════════════════════════
  //  关键：记录当前窗口实际大小，避免重复调用平台通道
  // ══════════════════════════════════════════════════════════════
  Size _currentWindowSize = const Size(120, 34);

  bool _isDragging = false;

  Future<WindowController> _getController() async {
    _windowController ??= await WindowController.fromCurrentEngine();
    return _windowController!;
  }

  @override
  void initState() {
    super.initState();
    _getController();

    _splitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _sizeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // ╔══════════════════════════════════════════════════════════╗
    // ║  不再 addListener —— 这就是闪退的根源                   ║
    // ║  Flutter 的 AnimatedBuilder 已经负责每帧渲染正确尺寸    ║
    // ║  窗口 resize 只在状态切换时做一次就够了                  ║
    // ╚══════════════════════════════════════════════════════════╝

    _sizeAnimation = Tween<Size>(
      begin: const Size(120, 34),
      end: const Size(120, 34),
    ).animate(CurvedAnimation(
      parent: _sizeController,
      curve: Curves.easeOutCubic,
    ));

    widget.payloadNotifier?.addListener(_onNotifierPayload);

    if (widget.initialPayload != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPayload(widget.initialPayload);
      });
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  只在目标尺寸确实变了的时候才调一次平台通道
  // ══════════════════════════════════════════════════════════════
  Future<void> _resizeWindowOnce(Size targetSize) async {
    if (targetSize == _currentWindowSize) return;

    try {
      final ctrl = await _getController();
      await ctrl.invokeMethod('setWindowSize', {
        'width': targetSize.width.toDouble(),
        'height': targetSize.height.toDouble(),
      });
      _currentWindowSize = targetSize;
    } catch (e) {
      debugPrint('[IslandUI] _resizeWindowOnce error: $e');
    }
  }

  @override
  void dispose() {
    _hoverDebounce?.cancel();
    _payloadDebounce?.cancel();
    _minStayTimer?.cancel();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _copiedLinkTimer?.cancel();
    _timeNotifier.dispose();
    widget.payloadNotifier?.removeListener(_onNotifierPayload);
    _splitController.dispose();
    _sizeController.dispose();
    _windowController?.setWindowMethodHandler(null);
    _windowController = null;
    super.dispose();
  }

  // ── 状态计算 ──────────────────────────────────────────────
  /// 仅做尺寸动画 + native resize，不改 _state（用于同状态内的尺寸变化）
  void _resizeWithAnimation(Size toSize) {
    if (!mounted) return;
    final Size fromSize = _sizeAnimation.value;
    if (fromSize == toSize) return;

    final int myVersion = ++_transitionVersion;
    _transitioning = true;

    _sizeAnimation = Tween<Size>(
      begin: fromSize,
      end: toSize,
    ).animate(CurvedAnimation(
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

  IslandState _computeNextState(String stateStr) {
    switch (stateStr) {
      case 'idle':
        return _isFocusing ? IslandState.focusing : IslandState.idle;
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

  // ── Payload 处理 ──────────────────────────────────────────

  void _onNotifierPayload() {
    _payloadDebounce?.cancel();
    _payloadDebounce = Timer(const Duration(milliseconds: 50), () {
      if (mounted) _applyPayload(widget.payloadNotifier?.value);
    });
  }

  void _applyPayload(Map<String, dynamic>? payload) {
    debugPrint(
        '[IslandUI] _applyPayload called: state=${payload?['state']}, _isFocusing will be=${payload?['state'] == 'focusing'}, currentTimer active=${_countdownTimer?.isActive}');
    if (payload == null || !mounted) return;
    _currentPayload = payload;

    final focusData = payload['focusData'] as Map?;
    final String stateStr = payload['state']?.toString() ?? 'idle';
    final rawReminderData = payload['reminderPopupData'];
    final reminderData = rawReminderData != null
        ? Map<String, dynamic>.from(rawReminderData as Map)
        : null;

    // 处理提醒弹出数据（支持所有状态，只要有时提醒数据）
    if (reminderData != null) {
      _reminderPopupData = reminderData;

      // 检查是否需要强提醒展开
      final needsExpand = reminderData['needsExpand'] as bool? ?? false;
      final acknowledged = reminderData['acknowledged'] as bool? ?? false;

      // 如果需要展开且未确认，自动展开
      if (needsExpand &&
          !acknowledged &&
          _expandedReminderPart == null &&
          _state == IslandState.reminderSplit) {
        debugPrint('[IslandUI] 需要强提醒展开');
        // 清除 needsExpand 标志避免重复展开
        _reminderPopupData = {
          ...reminderData,
          'needsExpand': false,
        };
        // 延迟展开确保窗口大小已调整
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _expandedReminderPart = 'reminder';
            });
            _resizeWithAnimation(_targetSizeFor(IslandState.reminderSplit));
          }
        });
      }
    } else if (stateStr != 'reminder_popup' &&
        stateStr != 'reminder_split' &&
        stateStr != 'reminder_capsule') {
      // 非提醒状态且没有提醒数据时，清除展开状态
      _expandedReminderPart = null;
    }

    final int endMs = focusData?['endMs'] ?? 0;

    // 关键修正：直接信任 state 字段，忽略残留数据
    // reminder_split 也需要显示专注倒计时
    _isFocusing = stateStr == 'focusing' || stateStr == 'reminder_split';

    final IslandState nextStateCandidate = _computeNextState(stateStr);

    final tl = focusData?['timeLabel']?.toString() ?? '';
    debugPrint(
        '[IslandUI] 收到 payload: state=$stateStr, endMs=$endMs, timeLabel=$tl, _isFocusing=$_isFocusing');
    debugPrint('[IslandUI] 计算结果: nextState=$nextStateCandidate');

    if (mounted) {
      setState(() {
        if (focusData != null && _isFocusing) {
          // 1. Determine countdown/count-up mode early as parsing depends on it
          _isCountdown = focusData['isCountdown'] ?? true;

          // 2. Prioritize parsing from timeLabel (works for both modes)
          if (tl.isNotEmpty) {
            _parseTimeLabel(tl);
          }
          // 3. Fallback: compute from endMs (only meaningful for countdown)
          else if (endMs > 0) {
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            _remainingSecs = ((endMs - nowMs) / 1000).round();
            if (_remainingSecs < 0) _remainingSecs = 0;
          }
        }
        // No longer handling timer cancellation here; moved to _ensureTimerRunning
      });
    }

    // 处理复制链接数据
    final rawCopiedLinkData = payload['copiedLinkData'];
    if (rawCopiedLinkData != null && stateStr == 'copied_link') {
      try {
        _copiedLinkData = Map<String, dynamic>.from(rawCopiedLinkData as Map);
      } catch (e) {
        _copiedLinkData = null;
      }
      if (_copiedLinkData != null) {
        _startCopiedLinkTimer();
      }
    }

    if (nextStateCandidate != _state) {
      // 保存当前状态以便在提醒弹出后恢复
      if (nextStateCandidate == IslandState.reminderPopup &&
          _state != IslandState.reminderPopup) {
        _savedStateBeforeReminder = _state;
      }

      // 保存当前状态以便在复制链接提醒后恢复
      if (nextStateCandidate == IslandState.copiedLink &&
          _state != IslandState.copiedLink) {
        _savedStateBeforeCopiedLink = _state;
      }

      if (_state == IslandState.hoverWide &&
          (nextStateCandidate == IslandState.idle ||
              nextStateCandidate == IslandState.focusing)) {
        _savedStateBeforeHover = nextStateCandidate;
      } else {
        _transitionToState(nextStateCandidate);
      }
    }

    _ensureTimerRunning();
  }

  // ── Hover ─────────────────────────────────────────────────

  void _onHoverEnter() {
    _hoverDebounce?.cancel();
    _isHovered = true;
    _canShrink = false; // 展开后禁止立即收缩
    _hoverDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!_isHovered || !mounted) return;
      if (_state == IslandState.idle || _state == IslandState.focusing) {
        _savedStateBeforeHover = _state;
        _transitionToState(IslandState.hoverWide);
        // 展开后 400ms 内禁止收缩
        _minStayTimer?.cancel();
        _minStayTimer = Timer(const Duration(milliseconds: 400), () {
          _canShrink = true;
        });
      }
    });
  }

  void _onHoverExit() {
    _hoverDebounce?.cancel();
    _isHovered = false;
    _hoverDebounce = Timer(const Duration(milliseconds: 120), () {
      if (_isHovered || !mounted) return;
      // 如果还在最小停留期内，延迟检查
      if (!_canShrink) {
        _hoverDebounce = Timer(const Duration(milliseconds: 200), () {
          if (_isHovered || !mounted) return;
          _doShrinkIfNeeded();
        });
        return;
      }
      _doShrinkIfNeeded();
    });
  }

  void _doShrinkIfNeeded() {
    if (_state == IslandState.hoverWide && _savedStateBeforeHover != null) {
      _transitionToState(_savedStateBeforeHover!);
      _savedStateBeforeHover = null;
    }
  }

  // ── 倒计时 ────────────────────────────────────────────────

  void _parseTimeLabel(String label) {
    if (label.isEmpty) return;
    final parts = label.split(':');
    try {
      if (parts.length == 2) {
        _remainingSecs = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } else if (parts.length == 3) {
        _remainingSecs = int.parse(parts[0]) * 3600 +
            int.parse(parts[1]) * 60 +
            int.parse(parts[2]);
      }
    } catch (_) {}
  }

  void _ensureTimerRunning() {
    // Unconditionally cancel and nullify existing timer to avoid leaks
    _countdownTimer?.cancel();
    _countdownTimer = null;

    if (!_isFocusing) {
      _updateDisplayTime();
      // 非专注状态下，降低频率至每分钟更新一次时钟即可
      _countdownTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        _updateDisplayTime();
      });
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isFocusing) {
        if (_isCountdown) {
          if (_remainingSecs > 0) _remainingSecs--;
        } else {
          _remainingSecs++;
        }
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
    final m = (_remainingSecs ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSecs % 60).toString().padLeft(2, '0');
    _timeNotifier.value = '$m:$s';
  }

  // ══════════════════════════════════════════════════════════════
  //  核心状态切换 —— 窗口 resize 只在这里调一次
  // ══════════════════════════════════════════════════════════════

  Size _targetSizeFor(IslandState s) {
    switch (s) {
      case IslandState.focusing:
        return const Size(100, 46);
      case IslandState.hoverWide:
        return const Size(380, 46); // 高度与 focusing 保持一致
      case IslandState.splitAlert:
        return const Size(300, 36);
      case IslandState.stackedCard:
        return const Size(280, 140);
      case IslandState.finishConfirm:
      case IslandState.abandonConfirm:
      case IslandState.finishFinal:
        return const Size(260, 130);
      case IslandState.reminderPopup:
        // 根据内容自适应高度
        final hasSubtitle = _reminderPopupData != null &&
            (_reminderPopupData!['subtitle']?.toString().isNotEmpty ?? false);
        return Size(320, hasSubtitle ? 180 : 150);
      case IslandState.reminderSplit:
        if (_expandedReminderPart != null) {
          final hasSubtitle = _reminderPopupData != null &&
              (_reminderPopupData!['subtitle']?.toString().isNotEmpty ?? false);
          // 46 + 8 + 卡片(~175/200) + 8
          return Size(320, hasSubtitle ? 340 : 300);
        }
        return const Size(480, 46);
      case IslandState.reminderCapsule:
        return const Size(160, 46);
      case IslandState.copiedLink:
        return const Size(340, 46);
      default:
        return const Size(120, 34);
    }
  }

  // 检查当前状态是否需要向下展开
  bool _needsDownwardExpansion(IslandState s) {
    if (s != IslandState.reminderSplit) return false;
    return _expandedReminderPart != null;
  }

  // 检查是否需要收起（从展开状态变为收起状态）
  bool _isShrinkingFromExpanded(IslandState prevState, IslandState nextState) {
    if (prevState != IslandState.reminderSplit) return false;
    // 如果之前有展开，现在没有，就是收起
    return _expandedReminderPart != null &&
        (nextState == IslandState.reminderSplit ||
            nextState == IslandState.idle);
  }

  void _transitionToState(IslandState nextState) {
    if (!mounted) return;

    // 🚀 使用版本号及状态检查实现并发保护
    final int myVersion = ++_transitionVersion;
    if (nextState == _state && !_transitioning) return;

    _transitioning = true;
    final prevState = _state;
    final Size fromSize = _sizeAnimation.value;
    final Size toSize = _targetSizeFor(nextState);

    debugPrint('[IslandUI] 状态切换 [$myVersion]: $_state -> $nextState');

    // 1) 先更新逻辑状态
    setState(() {
      _state = nextState;
    });

    // 2) split 动画
    if (nextState == IslandState.splitAlert) {
      _splitController.forward();
    } else if (prevState == IslandState.splitAlert) {
      _splitController.reverse();
    }

    // 3) 准备尺寸动画
    _sizeAnimation = Tween<Size>(
      begin: fromSize,
      end: toSize,
    ).animate(CurvedAnimation(
      parent: _sizeController,
      curve: Curves.easeOutCubic,
    ));

    // 4) 触发 native resize
    _resizeWindowOnce(toSize);

    // 5) 播放 Flutter 内部的尺寸动画
    _sizeController.forward(from: 0).then((_) {
      if (mounted && _transitionVersion == myVersion) {
        _transitioning = false;
        _doPostTransitionCorrection(myVersion);
      }
    });
  }

  void _doPostTransitionCorrection(int version) {
    if (!mounted || _transitionVersion != version) return;
    // 🚀 不再自动切换状态，避免与 hover 事件形成循环
    // hover 状态由 _onHoverEnter/_onHoverExit 通过 debounce 控制
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // reminderSplit 状态使用透明背景，让两个胶囊独立显示
    final bgColor = _state == IslandState.reminderSplit
        ? Colors.transparent
        : const Color(0xFF1C1C1E);
    final borderColor = Colors.black.withOpacity(0.5);

    return Material(
      color: Colors.transparent,
      child: MouseRegion(
        onEnter: (_) => _onHoverEnter(),
        onExit: (_) => _onHoverExit(),
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _sizeController,
            builder: (context, child) {
              final currentSize = _sizeAnimation.value;
              return Container(
                width: currentSize.width,
                height: currentSize.height,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(
                    _state == IslandState.stackedCard ||
                            _state == IslandState.finishConfirm ||
                            _state == IslandState.abandonConfirm ||
                            _state == IslandState.finishFinal ||
                            _state == IslandState.reminderSplit
                        ? 20
                        : 28,
                  ),
                  border: _state == IslandState.reminderSplit
                      ? null
                      : Border.all(color: borderColor, width: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.92, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                  child: _buildContent(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case IslandState.idle:
        return _buildIdle();
      case IslandState.focusing:
        return _buildFocusing();
      case IslandState.hoverWide:
        return _buildHoverWide();
      case IslandState.splitAlert:
        return _buildSplitAlert();
      case IslandState.stackedCard:
        return _buildStackedCard();
      case IslandState.finishConfirm:
        return _buildConfirm(mode: 'finish');
      case IslandState.abandonConfirm:
        return _buildConfirm(mode: 'abandon');
      case IslandState.finishFinal:
        return _buildConfirm(mode: 'final');
      case IslandState.reminderPopup:
        return _buildReminderPopup();
      case IslandState.reminderSplit:
        return _buildReminderSplit();
      case IslandState.reminderCapsule:
        return _buildReminderCapsule();
      case IslandState.copiedLink:
        return _buildCopiedLink();
    }
  }

  // ── 各状态 UI ─────────────────────────────────────────────

  Widget _buildIdle() {
    return GestureDetector(
      key: const ValueKey('idle'),
      onTap: () {
        if (_isFocusing) {
          _transitionToState(IslandState.focusing);
        } else {
          _transitionToState(IslandState.hoverWide);
        }
      },
      onPanStart: (_) => _startDragging(),
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: ValueListenableBuilder<String>(
          valueListenable: _timeNotifier,
          builder: (context, time, _) => Text(
            time,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFocusing() {
    final focusData = _currentPayload?['focusData'] as Map?;
    final title = focusData?['title']?.toString() ?? '专注事项';

    return GestureDetector(
      key: const ValueKey('focusing'),
      onTap: () => _transitionToState(IslandState.stackedCard),
      onPanStart: (_) => _startDragging(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            ValueListenableBuilder<String>(
              valueListenable: _timeNotifier,
              builder: (context, time, _) => Text(
                time,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoverWide() {
    final dashData = _currentPayload?['dashboardData'] as Map?;
    final legacy = _currentPayload?['legacy'] as Map?;

    final String left = dashData?['leftSlot']?.toString() ??
        _currentPayload?['topBarLeft']?.toString() ??
        legacy?['topBarLeft']?.toString() ??
        _currentPayload?['left']?.toString() ??
        legacy?['left']?.toString() ??
        '';
    final String right = dashData?['rightSlot']?.toString() ??
        _currentPayload?['topBarRight']?.toString() ??
        legacy?['topBarRight']?.toString() ??
        _currentPayload?['right']?.toString() ??
        legacy?['right']?.toString() ??
        '';

    return GestureDetector(
      key: const ValueKey('hoverWide'),
      onTap: () {
        if (_isFocusing) {
          _transitionToState(IslandState.stackedCard);
        } else {
          _transitionToState(IslandState.idle);
        }
      },
      onPanStart: (_) => _startDragging(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              flex: 2,
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
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: _timeNotifier,
                builder: (context, time, _) => Text(
                  time,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
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

  Widget _buildSplitAlert() {
    final reminderData = _currentPayload?['reminderData'] as Map?;
    final reminderTitle = reminderData?['title']?.toString() ?? '提醒事项';
    final reminderTime = reminderData?['detail_time']?.toString() ?? '';
    final type = reminderData?['type']?.toString() ?? 'course';

    IconData iconData = Icons.alarm;
    if (type == 'course') iconData = Icons.school;
    if (type == 'birthday') iconData = Icons.cake;
    if (type == 'todo') iconData = Icons.list;

    return Container(
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: ValueListenableBuilder<String>(
              valueListenable: _timeNotifier,
              builder: (context, time, _) => Text(
                time,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => _transitionToState(IslandState.stackedCard),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(iconData, color: Colors.white, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$reminderTitle ${reminderTime.isNotEmpty ? reminderTime : ""}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackedCard() {
    final focusData = _currentPayload?['focusData'] as Map?;
    final title = focusData?['title']?.toString() ?? '专注事项';
    final tags = (focusData?['tags'] as List?)?.join(' ') ?? '专注标签';
    final syncMode = focusData?['syncMode']?.toString() ?? 'local';
    final bool isLocal = syncMode == 'local';

    return GestureDetector(
      key: const ValueKey('stackedCard'),
      onTap: () => _transitionToState(IslandState.focusing),
      onPanStart: (_) => _startDragging(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: _timeNotifier,
              builder: (context, time, _) => Text(
                '$time | $title',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tags,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (!isLocal)
              _buildDesignBtn(
                label: '远端计时中，无法更改',
                color: Colors.white.withOpacity(0.1),
                onTap: () {},
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _buildDesignBtn(
                      label: '完成',
                      color: const Color(0xFF4CAF50),
                      onTap: () =>
                          _transitionToState(IslandState.finishConfirm),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDesignBtn(
                      label: '放弃',
                      color: const Color(0xFFD32F2F),
                      onTap: () =>
                          _transitionToState(IslandState.abandonConfirm),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirm({required String mode}) {
    String mainText = '';
    String okLabel = '确认';
    String cancelLabel = '手滑了';
    Color okColor = const Color(0xFF4CAF50);
    Color cancelColor = const Color(0xFFD32F2F);
    bool isReverse = false;

    if (mode == 'finish') {
      mainText = '确认完成?';
    } else if (mode == 'abandon') {
      mainText = '确认放弃?';
      isReverse = true;
    } else if (mode == 'final') {
      mainText = '专注完成';
      okLabel = '好的';
    }

    final focusData = _currentPayload?['focusData'] as Map?;
    final title = focusData?['title']?.toString() ?? '专注内容';
    final subText = '$title | ${_timeNotifier.value}';

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            mainText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          if (mode == 'final')
            _buildDesignBtn(
              label: okLabel,
              color: okColor,
              onTap: () => _transitionToState(IslandState.idle),
            )
          else
            Row(
              children: [
                if (!isReverse) ...[
                  Expanded(
                    child: _buildDesignBtn(
                      label: okLabel,
                      color: okColor,
                      onTap: () {
                        widget.onAction?.call(
                          mode == 'finish' ? 'finish' : 'abandon',
                          _remainingSecs,
                        );
                        _transitionToState(
                          mode == 'finish'
                              ? IslandState.finishFinal
                              : IslandState.idle,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDesignBtn(
                      label: cancelLabel,
                      color: cancelColor,
                      onTap: () => _transitionToState(IslandState.stackedCard),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: _buildDesignBtn(
                      label: cancelLabel,
                      color: okColor,
                      onTap: () => _transitionToState(IslandState.stackedCard),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDesignBtn(
                      label: okLabel,
                      color: cancelColor,
                      onTap: () {
                        widget.onAction?.call('abandon', 0);
                        _transitionToState(IslandState.idle);
                      },
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildReminderPopup() {
    final data = _reminderPopupData;
    if (data == null) return const SizedBox.shrink();

    final type = data['type']?.toString() ?? 'todo';
    final title = data['title']?.toString() ?? '';
    final subtitle = data['subtitle']?.toString() ?? '';
    final startTime = data['startTime']?.toString() ?? '';
    final endTime = data['endTime']?.toString() ?? '';
    final minutesUntil = data['minutesUntil'] as int? ?? 0;
    final isEnding = data['isEnding'] as bool? ?? false;

    final typeIcon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final typeLabel = type == 'course' ? '课程' : (type == 'todo' ? '待办' : '倒计时');
    final statusText =
        isEnding ? '还有 $minutesUntil 分钟结束' : '还有 $minutesUntil 分钟开始';

    return GestureDetector(
      key: const ValueKey('reminderPopup'),
      onPanStart: (_) => _startDragging(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 大标题
            Text(
              '$typeIcon $typeLabel：$title',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // 副标题（地点/备注）
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            // 时间和状态
            Text(
              '$startTime ~ $endTime  |  $statusText',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // 按钮
            Row(
              children: [
                Expanded(
                  child: _buildDesignBtn(
                    label: '好的',
                    color: const Color(0xFF4CAF50),
                    onTap: _onReminderOk,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDesignBtn(
                    label: '稍后提醒',
                    color: const Color(0xFFFF9800),
                    onTap: _onReminderLater,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onReminderOk() {
    final itemId = _reminderPopupData?['itemId']?.toString();
    if (itemId != null) {
      widget.onAction?.call('reminder_ok', 0);
    }
    _reminderPopupData = {
      ..._reminderPopupData ?? {},
      'acknowledged': true,
    };
    setState(() {
      _expandedReminderPart = null;
    });
    _transitionToState(IslandState.reminderCapsule);
  }

  void _onReminderLater() {
    widget.onAction?.call('remind_later', 0);
    setState(() {
      _expandedReminderPart = null;
    });
    _transitionToState(IslandState.reminderCapsule);
  }

  /// 构建分裂状态：点击切换展开/收起
  Widget _buildReminderSplit() {
    final data = _reminderPopupData;
    if (data == null) return const SizedBox.shrink();

    final type = data['type']?.toString() ?? 'todo';
    final title = data['title']?.toString() ?? '';
    final minutesUntil = data['minutesUntil'] as int? ?? 0;
    final isEnding = data['isEnding'] as bool? ?? false;

    final typeIcon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final statusText = isEnding ? '${minutesUntil}min' : '${minutesUntil}min';

    final isExpanded = _expandedReminderPart != null;

    // 两个胶囊始终在顶部，每个可单独点击展开
    final capsulesRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 专注胶囊点击
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isExpanded && _expandedReminderPart == 'focusing') {
              debugPrint('[IslandUI] 点击专注胶囊收起');
              setState(() => _expandedReminderPart = null);
            } else {
              debugPrint('[IslandUI] 点击专注胶囊展开');
              setState(() => _expandedReminderPart = 'focusing');
            }
            _resizeWithAnimation(_targetSizeFor(IslandState.reminderSplit));
          },
          child: _buildSplitFocusingCapsule(isExpanded: false),
        ),
        const SizedBox(width: 12),
        // 提醒胶囊点击
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isExpanded && _expandedReminderPart == 'reminder') {
              debugPrint('[IslandUI] 点击提醒胶囊收起');
              setState(() => _expandedReminderPart = null);
            } else {
              debugPrint('[IslandUI] 点击提醒胶囊展开');
              setState(() => _expandedReminderPart = 'reminder');
            }
            _resizeWithAnimation(_targetSizeFor(IslandState.reminderSplit));
          },
          child: _buildSplitReminderCapsule(typeIcon, title, statusText),
        ),
      ],
    );

    if (!isExpanded) {
      return KeyedSubtree(
        key: const ValueKey('reminderSplit'), // ← 固定 key
        child: Center(child: capsulesRow),
      );
    }

    // 展开时：Stack 让胶囊固定在顶部，根据展开类型显示对应卡片
    final expandedCard = _expandedReminderPart == 'focusing'
        ? _buildSplitFocusingExpanded()
        : _buildSplitReminderExpanded();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 胶囊行 —— 固定在顶部
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 46,
          child: Center(child: capsulesRow),
        ),
        // 展开的卡片 —— 从胶囊底部往下延伸
        Positioned(
          top: 46 + 8, // 胶囊高度 + 间距
          left: 8,
          right: 8,
          child: expandedCard,
        ),
      ],
    );
  }

  /// 分裂状态下专注胶囊展开时显示的 stackedCard 样式
  Widget _buildSplitFocusingExpanded() {
    final focusData = _currentPayload?['focusData'] as Map?;
    final focusTitle = focusData?['title']?.toString() ?? '自由专注';
    final focusTags = (focusData?['tags'] as List?)?.join(' ') ?? '';

    return Container(
      width: 260,
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.5), width: 0.8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: _timeNotifier,
            builder: (context, time, _) => Text(
              '$time | $focusTitle',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            focusTags,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDesignBtn(
                  label: '完成',
                  color: const Color(0xFF4CAF50),
                  onTap: () {
                    widget.onAction?.call('finish', _remainingSecs);
                    _transitionToState(IslandState.finishConfirm);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDesignBtn(
                  label: '放弃',
                  color: const Color(0xFFD32F2F),
                  onTap: () {
                    widget.onAction?.call('abandon', 0);
                    _transitionToState(IslandState.abandonConfirm);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 分裂状态下提醒胶囊展开时显示的详细大卡片
  Widget _buildSplitReminderExpanded() {
    final data = _reminderPopupData;
    if (data == null) return const SizedBox.shrink();

    final type = data['type']?.toString() ?? 'todo';
    final title = data['title']?.toString() ?? '';
    final subtitle = data['subtitle']?.toString() ?? '';
    final startTime = data['startTime']?.toString() ?? '';
    final endTime = data['endTime']?.toString() ?? '';
    final minutesUntil = data['minutesUntil'] as int? ?? 0;
    final isEnding = data['isEnding'] as bool? ?? false;

    final typeIcon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final typeLabel = type == 'course' ? '课程' : (type == 'todo' ? '待办' : '倒计时');
    final statusText =
        isEnding ? '还有 $minutesUntil 分钟结束' : '还有 $minutesUntil 分钟开始';

    return Container(
      width: double.infinity, // ← 改这里，跟随父级宽度
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.5), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$typeIcon $typeLabel：$title',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '$startTime ~ $endTime  |  $statusText',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDesignBtn(
                  label: '好的',
                  color: const Color(0xFF4CAF50),
                  onTap: _onReminderOk,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDesignBtn(
                  label: '稍后提醒',
                  color: const Color(0xFFFF9800),
                  onTap: _onReminderLater,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 提醒胶囊展开时的紧凑大卡片
  Widget _buildReminderPopupCompact() {
    final data = _reminderPopupData;
    if (data == null) return const SizedBox.shrink();

    final type = data['type']?.toString() ?? 'todo';
    final title = data['title']?.toString() ?? '';
    final subtitle = data['subtitle']?.toString() ?? '';
    final startTime = data['startTime']?.toString() ?? '';
    final endTime = data['endTime']?.toString() ?? '';
    final minutesUntil = data['minutesUntil'] as int? ?? 0;
    final isEnding = data['isEnding'] as bool? ?? false;

    final typeIcon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final timeText = isEnding ? '已超时 $minutesUntil 分钟' : '$minutesUntil 分钟后开始';

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withOpacity(0.9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(typeIcon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${minutesUntil}min',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 分裂状态下的专注胶囊（独立样式）
  Widget _buildSplitFocusingCapsule({bool isExpanded = false}) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎯', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          ValueListenableBuilder<String>(
            valueListenable: _timeNotifier,
            builder: (context, time, _) => Text(
              time,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分裂状态下的提醒胶囊（独立样式）
  Widget _buildSplitReminderCapsule(
      String typeIcon, String title, String statusText) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withOpacity(0.9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(typeIcon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 60),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建提醒胶囊状态：常驻显示的提醒胶囊
  Widget _buildReminderCapsule() {
    final data = _reminderPopupData;
    if (data == null) return const SizedBox.shrink();

    final type = data['type']?.toString() ?? 'todo';
    final title = data['title']?.toString() ?? '';
    final minutesUntil = data['minutesUntil'] as int? ?? 0;
    final isEnding = data['isEnding'] as bool? ?? false;

    final typeIcon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final statusText = isEnding ? '${minutesUntil}min' : '${minutesUntil}min';

    return GestureDetector(
      key: const ValueKey('reminderCapsule'),
      onPanStart: (_) => _startDragging(),
      onTap: () {
        // 点击展开大卡片
        _savedStateBeforeReminder = IslandState.reminderCapsule;
        _transitionToState(IslandState.reminderPopup);
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withOpacity(0.9),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                typeIcon,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCopiedLink() {
    final data = _copiedLinkData;
    if (data == null) return const SizedBox.shrink();

    final url = data['url']?.toString() ?? '';
    final displayUrl = data['displayUrl']?.toString() ?? _truncateUrl(url);

    return GestureDetector(
      key: const ValueKey('copiedLink'),
      onPanStart: (_) => _startDragging(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Text('🔗', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '已复制: $displayUrl',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildMiniBtn(
              label: '打开',
              color: const Color(0xFF4CAF50),
              onTap: () => _onOpenLink(),
            ),
            const SizedBox(width: 6),
            _buildMiniBtn(
              label: '✕',
              color: Colors.white.withOpacity(0.2),
              onTap: () => _onDismissLink(),
            ),
          ],
        ),
      ),
    );
  }

  String _truncateUrl(String url) {
    if (url.length <= 25) return url;
    return '${url.substring(0, 25)}...';
  }

  void _onOpenLink() {
    _copiedLinkTimer?.cancel();
    final url = _copiedLinkData?['url']?.toString();
    if (url != null) {
      widget.onAction?.call('open_link', 0);
    }
    _restorePreviousState();
  }

  void _onDismissLink() {
    _copiedLinkTimer?.cancel();
    _restorePreviousState();
  }

  void _restorePreviousState() {
    if (_savedStateBeforeCopiedLink != null) {
      _transitionToState(_savedStateBeforeCopiedLink!);
      _savedStateBeforeCopiedLink = null;
    } else {
      _transitionToState(IslandState.idle);
    }
    _copiedLinkData = null;
  }

  void _startCopiedLinkTimer() {
    _copiedLinkTimer?.cancel();
    _copiedLinkTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _state == IslandState.copiedLink) {
        _restorePreviousState();
      }
    });
  }

  Widget _buildMiniBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
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
  }

  Widget _buildDesignBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
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
  }

  void _startDragging() async {
    _isDragging = true;
    try {
      final controller = await _getController();
      await controller.invokeMethod('startDragging');

      Future.delayed(const Duration(milliseconds: 100), () {
        _isDragging = false;
      });
    } catch (_) {
      _isDragging = false;
    }
  }
}
