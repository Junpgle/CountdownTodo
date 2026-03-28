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
  bool _isHovered = false;

  WindowController? _windowController;

  // ══════════════════════════════════════════════════════════════
  //  关键：记录当前窗口实际大小，避免重复调用平台通道
  // ══════════════════════════════════════════════════════════════
  Size _currentWindowSize = const Size(120, 34);

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
      duration: const Duration(milliseconds: 300),
    );

    _sizeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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
      curve: Curves.easeInOutQuart,
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
    if (targetSize == _currentWindowSize) return; // 尺寸没变就跳过
    try {
      final ctrl = await _getController();
      await ctrl.invokeMethod('setWindowSize', {
        'width': targetSize.width.toDouble(),
        'height': targetSize.height.toDouble(),
      });
      // 🚀 仅在调用成功后再更新本地状态，确保失败后可重试
      _currentWindowSize = targetSize;
    } catch (e) {
      debugPrint('[IslandUI] _resizeWindowOnce error: $e');
    }
  }

  @override
  void dispose() {
    _hoverDebounce?.cancel();
    _payloadDebounce?.cancel();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _timeNotifier.dispose();
    widget.payloadNotifier?.removeListener(_onNotifierPayload);
    _splitController.dispose();
    _sizeController.dispose();
    _windowController?.setWindowMethodHandler(null);
    _windowController = null;
    super.dispose();
  }

  // ── 状态计算 ──────────────────────────────────────────────

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

    final int endMs = focusData?['endMs'] ?? 0;

    // 关键修正：直接信任 state 字段，忽略残留数据
    _isFocusing = stateStr == 'focusing';

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

    if (nextStateCandidate != _state) {
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
    _hoverDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!_isHovered || !mounted) return;
      if (_state == IslandState.idle || _state == IslandState.focusing) {
        _savedStateBeforeHover = _state;
        _transitionToState(IslandState.hoverWide);
      }
    });
  }

  void _onHoverExit() {
    _hoverDebounce?.cancel();
    _isHovered = false;
    _hoverDebounce = Timer(const Duration(milliseconds: 200), () {
      if (_isHovered || !mounted) return;
      if (_state == IslandState.hoverWide && _savedStateBeforeHover != null) {
        _transitionToState(_savedStateBeforeHover!);
        _savedStateBeforeHover = null;
      }
    });
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

  static Size _targetSizeFor(IslandState s) {
    switch (s) {
      case IslandState.focusing:
        return const Size(100, 46);
      case IslandState.hoverWide:
        return const Size(380, 34);
      case IslandState.splitAlert:
        return const Size(300, 36);
      case IslandState.stackedCard:
        return const Size(280, 140);
      case IslandState.finishConfirm:
      case IslandState.abandonConfirm:
      case IslandState.finishFinal:
        return const Size(260, 130);
      default:
        return const Size(120, 34);
    }
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

    // 1) 先更新逻辑状态（让内容切换）
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
      curve: Curves.easeInOutQuart,
    ));

    // 4) 只有当前版本才触发 native resize
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_transitionVersion == myVersion) {
        _resizeWindowOnce(toSize);
      }
    });

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
    final bgColor = const Color(0xFF1C1C1E);
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
                            _state == IslandState.finishFinal
                        ? 20
                        : 28,
                  ),
                  border: Border.all(color: borderColor, width: 0.8),
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
    try {
      final controller = await _getController();
      await controller.invokeMethod('startDragging');
    } catch (_) {}
  }
}
