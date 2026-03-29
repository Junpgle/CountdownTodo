import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:async';
import 'dart:ui';
import 'island_config.dart';
import 'island_state_stack.dart';

// Re-export IslandState for backward compatibility
export 'island_state_stack.dart' show IslandState;

class IslandUI extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final void Function(String action, [int? modifiedSecs, String? data])?
      onAction;
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
  Timer? _countdownTimer;
  int _remainingSecs = 0;
  bool _isCountdown = true;

  // ── 动画状态
  bool _transitioning = false;
  int _transitionVersion = 0;

  // ── Hover 相关
  Timer? _hoverDebounce;
  Timer? _minStayTimer;
  bool _isHovered = false;
  bool _canShrink = true;

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
    _getController();

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

    widget.payloadNotifier?.addListener(_onNotifierPayload);

    if (widget.initialPayload != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPayload(widget.initialPayload);
      });
    }
  }

  @override
  void dispose() {
    _hoverDebounce?.cancel();
    _minStayTimer?.cancel();
    _payloadDebounce?.cancel();
    _countdownTimer?.cancel();
    _autoDismissTimer?.cancel();
    _snoozeTimer?.cancel();
    _timeNotifier.dispose();
    widget.payloadNotifier?.removeListener(_onNotifierPayload);
    _splitController.dispose();
    _sizeController.dispose();
    _windowController?.setWindowMethodHandler(null);
    super.dispose();
  }

  // ── 窗口大小控制 ─────────────────────────────────────────────────────────

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
      debugPrint('[IslandUI] resize error: $e');
    }
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
    setState(() {}); // 触发 _buildContent() 读取 _stack.current

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
    final copiedLinkData = payload['copiedLinkData'] as Map<String, dynamic>?;
    if (copiedLinkData != null && stateStr == 'copied_link') {
      _pushWithAutoDismiss(
        IslandState.copiedLink,
        data: payload,
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
    final tl = fd['timeLabel']?.toString() ?? '';
    final endMs = fd['endMs'] ?? 0;

    if (tl.isNotEmpty) {
      _parseTimeLabel(tl);
    } else if (endMs > 0) {
      _remainingSecs =
          (((endMs - DateTime.now().millisecondsSinceEpoch) / 1000).round())
              .clamp(0, 999999);
    }
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

  // ── Hover 处理 ───────────────────────────────────────────────────────────

  void _onHoverEnter() {
    _hoverDebounce?.cancel();
    _isHovered = true;
    _canShrink = false;
    _hoverDebounce = Timer(IslandConfig.hoverEnterDelay, () {
      if (!_isHovered || !mounted) return;
      // reminderSplit / reminderCapsule / reminderPopup 状态下禁止 hover 展开
      // 也只在栈顶就是 base（即没有其他 overlay）时才展开
      final cur = _stack.current;
      final base = _stack.base;
      final isReminderState = cur == IslandState.reminderSplit ||
          cur == IslandState.reminderCapsule ||
          cur == IslandState.reminderPopup;
      final isBaseVisible = cur == base; // 栈顶 == 栈底，没有 overlay
      if (!isReminderState &&
          isBaseVisible &&
          (base == IslandState.idle || base == IslandState.focusing)) {
        _stack.push(IslandState.hoverWide, data: _currentPayload);
        _animateToState(IslandState.hoverWide);
        _minStayTimer?.cancel();
        _minStayTimer = Timer(IslandConfig.hoverMinStay, () {
          _canShrink = true;
        });
      } else {
        // 不展开时也要重置 _canShrink，否则后续 exit 会卡住
        _canShrink = true;
      }
    });
  }

  void _onHoverExit() {
    _hoverDebounce?.cancel();
    _isHovered = false;
    _hoverDebounce = Timer(IslandConfig.hoverExitDelay, () {
      if (_isHovered || !mounted) return;
      if (!_canShrink) {
        _hoverDebounce = Timer(const Duration(milliseconds: 200), () {
          if (!_isHovered) _doShrink();
        });
        return;
      }
      _doShrink();
    });
  }

  void _doShrink() {
    if (_stack.current == IslandState.hoverWide) {
      final restored = _stack.pop(IslandState.hoverWide);
      _animateToState(restored);
    }
  }

  // ── 时间处理 ─────────────────────────────────────────────────────────────

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

  Size _targetSizeFor(IslandState s) {
    final hasSub =
        _reminderPopupData?['subtitle']?.toString().isNotEmpty ?? false;
    switch (s) {
      case IslandState.idle:
        return const Size(120, 34);
      case IslandState.focusing:
        return const Size(100, 46);
      case IslandState.hoverWide:
        return const Size(380, 46);
      case IslandState.splitAlert:
        return const Size(300, 36);
      case IslandState.stackedCard:
        return const Size(280, 140);
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
        return const Size(340, 46);
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
      child: MouseRegion(
        onEnter: (_) => _onHoverEnter(),
        onExit: (_) => _onHoverExit(),
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _sizeController,
            builder: (_, __) => Container(
              width: _sizeAnimation.value.width,
              height: _sizeAnimation.value.height,
              decoration: BoxDecoration(
                color:
                    isTransparent ? Colors.transparent : IslandConfig.bgColor,
                borderRadius: BorderRadius.circular(isCard
                    ? IslandConfig.cardRadius
                    : IslandConfig.capsuleRadius),
                border: isTransparent
                    ? null
                    : Border.all(
                        color: Colors.black.withOpacity(0.5), width: 0.8),
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
                duration: IslandConfig.switchDuration,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1.0).animate(anim),
                    child: child,
                  ),
                ),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_stack.current) {
      case IslandState.idle:
        return _buildIdle();
      case IslandState.focusing:
        return _buildFocusing();
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

  // ── Idle ─────────────────────────────────────────────────────────────────

  Widget _buildIdle() => GestureDetector(
        key: const ValueKey('idle'),
        onTap: () {
          if (_isFocusing) {
            _stack.replaceBase(IslandState.focusing, data: _currentPayload);
            _animateToState(IslandState.focusing);
          } else {
            _stack.push(IslandState.hoverWide, data: _currentPayload);
            _animateToState(IslandState.hoverWide);
          }
        },
        onPanStart: (_) => _startDrag(),
        child: Container(
          color: Colors.transparent,
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
        ),
      );

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
      child: Container(
        color: Colors.transparent,
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
      ),
    );
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
                color: Colors.white.withOpacity(0.1),
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
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? '专注事项';
    final tags = (fd?['tags'] as List?)?.join(' ') ?? '';
    final isLocal = fd?['syncMode']?.toString() != 'remote';

    return GestureDetector(
      key: const ValueKey('stackedCard'),
      // 点击空白 → pop stackedCard，恢复 focusing
      onTap: () {
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
              valueListenable: _timeNotifier,
              builder: (_, t, __) => Text(
                '$t | $title',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
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
              _btn('远端计时中，无法更改', Colors.white.withOpacity(0.1), () {})
            else
              Row(
                children: [
                  // 点击完成 → push finishConfirm
                  Expanded(
                    child: _btn('完成', IslandConfig.successColor, () {
                      _stack.push(IslandState.finishConfirm,
                          data: _currentPayload);
                      _animateToState(IslandState.finishConfirm);
                    }),
                  ),
                  const SizedBox(width: 12),
                  // 点击放弃 → push abandonConfirm
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

  // ── CopiedLink ───────────────────────────────────────────────────────────

  Widget _buildCopiedLink() {
    final d = _currentPayload?['copiedLinkData'] as Map?;
    if (d == null) return const SizedBox.shrink();
    final url = d['url']?.toString() ?? '';
    final display = d['displayUrl']?.toString() ??
        (url.length > 25 ? '${url.substring(0, 25)}...' : url);

    return GestureDetector(
      key: const ValueKey('copiedLink'),
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
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
            // 打开 → 发 action，pop copiedLink
            _miniBtn('打开', IslandConfig.successColor, () {
              widget.onAction?.call('open_link', 0, url);
              _autoDismissTimer?.cancel();
              final restored = _stack.pop(IslandState.copiedLink);
              _animateToState(restored);
            }),
            const SizedBox(width: 6),
            // ✕ → pop copiedLink
            _miniBtn('✕', Colors.white.withOpacity(0.2), () {
              _autoDismissTimer?.cancel();
              final restored = _stack.pop(IslandState.copiedLink);
              _animateToState(restored);
            }),
          ],
        ),
      ),
    );
  }

  // ── ReminderPopup ────────────────────────────────────────────────────────

  Widget _buildReminderPopup() {
    final d = _reminderPopupData;
    if (d == null) return const SizedBox.shrink();

    final type = d['type']?.toString() ?? 'todo';
    final icon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final label = type == 'course' ? '课程' : (type == 'todo' ? '待办' : '倒计时');
    final mins = d['minutesUntil'] as int? ?? 0;
    final isEnd = d['isEnding'] as bool? ?? false;
    final status = isEnd ? '还有 $mins 分钟结束' : '还有 $mins 分钟开始';
    final itemId = d['itemId']?.toString();

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
            Text(
              '$icon $label：${d['title']}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if ((d['subtitle'] ?? '').toString().isNotEmpty)
              Text(
                d['subtitle'],
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
                    // 标记此提醒已确认
                    if (itemId != null) {
                      _acknowledgedReminderIds.add(itemId);
                    }
                    _reminderPopupData = null;
                    final restored = _stack.pop(IslandState.reminderPopup);
                    _animateToState(restored);
                  }),
                ),
                const SizedBox(width: 12),
                // 稍后提醒 → 发 action，标记已确认，pop 回 reminderCapsule
                Expanded(
                  child: _btn('稍后提醒', IslandConfig.warningColor, () {
                    debugPrint('[IslandUI] remind_later clicked (popup)');
                    widget.onAction?.call('remind_later', 0);
                    // 标记此提醒已确认
                    if (itemId != null) {
                      _acknowledgedReminderIds.add(itemId);
                    }
                    _reminderPopupData = null;
                    final restored = _stack.pop(IslandState.reminderPopup);
                    _animateToState(restored);
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
    if (d == null) return const SizedBox.shrink();

    final type = d['type']?.toString() ?? 'todo';
    final icon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final mins = '${d['minutesUntil'] as int? ?? 0}min';
    final expanded = _expandedReminderPart;

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final newExpanded = expanded == 'focusing' ? null : 'focusing';
            setState(() {
              _expandedReminderPart = newExpanded;
            });
            // 使用 Future.microtask 延迟执行，避免在 setState 中触发动画
            Future.microtask(() => _animateToState(IslandState.reminderSplit));
          },
          child: _capsule('🎯', _timeNotifier.value, IslandConfig.focusColor),
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
          child:
              _capsule(icon, '${d['title']} $mins', IslandConfig.warningColor),
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
          color: color.withOpacity(0.9),
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

  Widget _expandedFocusing() {
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? '自由专注';
    return Container(
      width: 260,
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IslandConfig.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.5), width: 0.8),
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

    final type = d['type']?.toString() ?? 'todo';
    final icon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final label = type == 'course' ? '课程' : (type == 'todo' ? '待办' : '倒计时');
    final mins = d['minutesUntil'] as int? ?? 0;
    final isEnd = d['isEnding'] as bool? ?? false;
    final status = isEnd ? '还有 $mins 分钟结束' : '还有 $mins 分钟开始';
    final itemId = d['itemId']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IslandConfig.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$icon $label：${d['title']}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if ((d['subtitle'] ?? '').toString().isNotEmpty)
            Text(
              d['subtitle'],
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
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
                  // 标记此提醒已确认
                  if (itemId != null) {
                    _acknowledgedReminderIds.add(itemId);
                  }
                  // 清除提醒数据
                  _reminderPopupData = null;
                  _expandedReminderPart = null;
                  // 恢复 focusing 状态
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
                  // 标记此提醒已确认（稍后会重新触发）
                  if (itemId != null) {
                    _acknowledgedReminderIds.add(itemId);
                  }
                  // 收起展开卡片，但保持双胶囊状态
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

    final type = d['type']?.toString() ?? 'todo';
    final icon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');

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
        child: _capsule(icon, '${d['title']} ${d['minutesUntil']}min',
            IslandConfig.warningColor),
      ),
    );
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
}
