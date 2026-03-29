import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:async';
import 'dart:ui';
import 'island_config.dart';
import 'island_state_handler.dart';

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
  int _lastTransitionMs = 0;
  bool _canShrink = true;

  Map<String, dynamic>? _reminderPopupData;
  IslandState? _savedStateBeforeReminder;
  String? _expandedReminderPart;

  Map<String, dynamic>? _copiedLinkData;
  IslandState? _savedStateBeforeCopiedLink;
  Timer? _copiedLinkTimer;
  Map<String, dynamic>? _cachedHoverWidePayload;
  Timer? _snoozeTimer;

  WindowController? _windowController;
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
    _snoozeTimer?.cancel();
    _timeNotifier.dispose();
    widget.payloadNotifier?.removeListener(_onNotifierPayload);
    _splitController.dispose();
    _sizeController.dispose();
    _windowController?.setWindowMethodHandler(null);
    _windowController = null;
    super.dispose();
  }

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

  void _onNotifierPayload() {
    _payloadDebounce?.cancel();
    _payloadDebounce = Timer(IslandConfig.payloadDebounce, () {
      if (mounted) _applyPayload(widget.payloadNotifier?.value);
    });
  }

  void _applyPayload(Map<String, dynamic>? payload) {
    debugPrint('[IslandUI] _applyPayload: state=${payload?['state']}');
    if (payload == null || !mounted) return;

    final String incomingStateStr = payload['state']?.toString() ?? 'idle';

    if (_state == IslandState.copiedLink && incomingStateStr != 'copied_link') {
      _ensureTimerRunning();
      return;
    }
    final isReminderState = _state == IslandState.reminderSplit ||
        _state == IslandState.reminderCapsule;
    final isReminderIncoming = incomingStateStr == 'reminder_split' ||
        incomingStateStr == 'reminder_capsule' ||
        incomingStateStr == 'reminder_popup';
    if (isReminderState &&
        !isReminderIncoming &&
        incomingStateStr != 'copied_link' &&
        incomingStateStr != 'snooze_reminder' &&
        incomingStateStr != 'idle') {
      _ensureTimerRunning();
      return;
    }
    if (_state == IslandState.reminderPopup &&
        incomingStateStr != 'reminder_popup' &&
        incomingStateStr != 'copied_link') {
      _ensureTimerRunning();
      return;
    }

    _currentPayload = payload;
    final focusData = payload['focusData'] as Map?;
    final String stateStr = payload['state']?.toString() ?? 'idle';

    if (stateStr == 'snooze_reminder') {
      final snoozeMinutes = payload['snoozeMinutes'] as int? ?? 5;
      if (_reminderPopupData != null) {
        _reminderPopupData = {
          ..._reminderPopupData!,
          'minutesUntil': snoozeMinutes,
          'acknowledged': false,
          'needsExpand': true,
        };
        final targetState = _isFocusing
            ? IslandState.reminderSplit
            : IslandState.reminderCapsule;
        _transitionToState(targetState);
        _snoozeTimer?.cancel();
        _snoozeTimer = Timer(Duration(minutes: snoozeMinutes), () {
          if (mounted &&
              _reminderPopupData != null &&
              !(_reminderPopupData!['acknowledged'] as bool? ?? false)) {
            setState(() {
              _expandedReminderPart = 'reminder';
            });
            _resizeWithAnimation(_targetSizeFor(targetState));
          }
        });
      }
      return;
    }

    final rawReminderData = payload['reminderPopupData'];
    final reminderData = rawReminderData != null
        ? Map<String, dynamic>.from(rawReminderData as Map)
        : null;

    if (reminderData != null) {
      _reminderPopupData = reminderData;
      final needsExpand = reminderData['needsExpand'] as bool? ?? false;
      final acknowledged = reminderData['acknowledged'] as bool? ?? false;

      if (needsExpand &&
          !acknowledged &&
          _expandedReminderPart == null &&
          _state == IslandState.reminderSplit) {
        _reminderPopupData = {
          ...reminderData,
          'needsExpand': false,
        };
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
      _expandedReminderPart = null;
    }

    final int endMs = focusData?['endMs'] ?? 0;
    _isFocusing = stateStr == 'focusing' || stateStr == 'reminder_split';
    final IslandState nextStateCandidate = _computeNextState(stateStr);
    final tl = focusData?['timeLabel']?.toString() ?? '';

    if (mounted) {
      setState(() {
        if (focusData != null && _isFocusing) {
          _isCountdown = focusData['isCountdown'] ?? true;
          if (tl.isNotEmpty) {
            _parseTimeLabel(tl);
          } else if (endMs > 0) {
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            _remainingSecs = ((endMs - nowMs) / 1000).round();
            if (_remainingSecs < 0) _remainingSecs = 0;
          }
        }
      });
    }

    final rawCopiedLinkData = payload['copiedLinkData'];
    if (rawCopiedLinkData != null) {
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
      if (nextStateCandidate == IslandState.reminderPopup &&
          _state != IslandState.reminderPopup) {
        _savedStateBeforeReminder = _state;
      }
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

  void _onHoverEnter() {
    _hoverDebounce?.cancel();
    _isHovered = true;
    _canShrink = false;
    _hoverDebounce = Timer(IslandConfig.hoverEnterDelay, () {
      if (!_isHovered || !mounted) return;
      if (_state == IslandState.idle || _state == IslandState.focusing) {
        _savedStateBeforeHover = _state;
        _transitionToState(IslandState.hoverWide);
        _minStayTimer?.cancel();
        _minStayTimer = Timer(IslandConfig.hoverMinStay, () {
          _canShrink = true;
        });
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
    _countdownTimer = null;

    if (!_isFocusing) {
      _updateDisplayTime();
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

  Size _targetSizeFor(IslandState s) {
    final hasSubtitle = _reminderPopupData != null &&
        (_reminderPopupData!['subtitle']?.toString().isNotEmpty ?? false);
    return IslandConfig.sizeForState(
      _stateToConfig(s),
      hasSubtitle: hasSubtitle,
      expandedPart: _expandedReminderPart,
    );
  }

  IslandStateConfig _stateToConfig(IslandState s) {
    switch (s) {
      case IslandState.idle:
        return IslandStateConfig.idle;
      case IslandState.focusing:
        return IslandStateConfig.focusing;
      case IslandState.hoverWide:
        return IslandStateConfig.hoverWide;
      case IslandState.splitAlert:
        return IslandStateConfig.splitAlert;
      case IslandState.stackedCard:
        return IslandStateConfig.stackedCard;
      case IslandState.finishConfirm:
        return IslandStateConfig.finishConfirm;
      case IslandState.abandonConfirm:
        return IslandStateConfig.abandonConfirm;
      case IslandState.finishFinal:
        return IslandStateConfig.finishFinal;
      case IslandState.reminderPopup:
        return IslandStateConfig.reminderPopup;
      case IslandState.reminderSplit:
        return IslandStateConfig.reminderSplit;
      case IslandState.reminderCapsule:
        return IslandStateConfig.reminderCapsule;
      case IslandState.copiedLink:
        return IslandStateConfig.copiedLink;
    }
  }

  void _transitionToState(IslandState nextState) {
    if (!mounted) return;

    final int myVersion = ++_transitionVersion;
    if (nextState == _state && !_transitioning) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastTransitionMs < IslandConfig.transitionDebounceMs &&
        ((nextState == IslandState.focusing &&
                _state == IslandState.reminderSplit) ||
            (nextState == IslandState.reminderSplit &&
                _state == IslandState.focusing))) {
      return;
    }
    _lastTransitionMs = nowMs;

    _transitioning = true;
    final prevState = _state;
    final Size fromSize = _sizeAnimation.value;
    final Size toSize = _targetSizeFor(nextState);

    if (nextState == IslandState.hoverWide && _currentPayload != null) {
      _cachedHoverWidePayload = Map<String, dynamic>.from(_currentPayload!);
    }

    setState(() {
      _state = nextState;
    });

    if (nextState == IslandState.splitAlert) {
      _splitController.forward();
    } else if (prevState == IslandState.splitAlert) {
      _splitController.reverse();
    }

    if ((nextState == IslandState.reminderSplit ||
            nextState == IslandState.reminderCapsule) &&
        _reminderPopupData != null) {
      final needsExpand = _reminderPopupData!['needsExpand'] as bool? ?? false;
      final acknowledged =
          _reminderPopupData!['acknowledged'] as bool? ?? false;
      if (needsExpand && !acknowledged && _expandedReminderPart == null) {
        _reminderPopupData = {
          ..._reminderPopupData!,
          'needsExpand': false,
        };
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              _expandedReminderPart = 'reminder';
            });
            _resizeWithAnimation(_targetSizeFor(nextState));
          }
        });
      }
    }

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

  @override
  Widget build(BuildContext context) {
    final bgColor = _state == IslandState.reminderSplit
        ? IslandConfig.transparentBg
        : IslandConfig.bgColor;
    final borderColor = Colors.black.withOpacity(0.5);

    final isCardState = _state == IslandState.stackedCard ||
        _state == IslandState.finishConfirm ||
        _state == IslandState.abandonConfirm ||
        _state == IslandState.finishFinal ||
        _state == IslandState.reminderSplit;
    final borderRadius =
        isCardState ? IslandConfig.cardRadius : IslandConfig.capsuleRadius;

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
                  borderRadius: BorderRadius.circular(borderRadius),
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
                  duration: IslandConfig.switchDuration,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: IslandConfig.switchScaleBegin,
                        end: IslandConfig.switchScaleEnd,
                      ).animate(animation),
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
    final effectivePayload =
        (_currentPayload?['dashboardData'] as Map?)?.isNotEmpty == true ||
                _currentPayload?['topBarLeft'] != null ||
                _currentPayload?['topBarRight'] != null ||
                _currentPayload?['left'] != null ||
                _currentPayload?['right'] != null
            ? _currentPayload
            : _cachedHoverWidePayload ?? _currentPayload;

    final dashData = effectivePayload?['dashboardData'] as Map?;
    final legacy = effectivePayload?['legacy'] as Map?;

    final String left = dashData?['leftSlot']?.toString() ??
        effectivePayload?['topBarLeft']?.toString() ??
        legacy?['topBarLeft']?.toString() ??
        effectivePayload?['left']?.toString() ??
        legacy?['left']?.toString() ??
        '';
    final String right = dashData?['rightSlot']?.toString() ??
        effectivePayload?['topBarRight']?.toString() ??
        legacy?['topBarRight']?.toString() ??
        effectivePayload?['right']?.toString() ??
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
                      color: IslandConfig.successColor,
                      onTap: () =>
                          _transitionToState(IslandState.finishConfirm),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDesignBtn(
                      label: '放弃',
                      color: IslandConfig.dangerColor,
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
    Color okColor = IslandConfig.successColor;
    Color cancelColor = IslandConfig.dangerColor;
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
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDesignBtn(
                    label: '好的',
                    color: IslandConfig.successColor,
                    onTap: _onReminderOk,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDesignBtn(
                    label: '稍后提醒',
                    color: IslandConfig.warningColor,
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
    if (_state == IslandState.reminderSplit) {
      _resizeWithAnimation(_targetSizeFor(IslandState.reminderSplit));
    } else {
      _transitionToState(IslandState.reminderCapsule);
    }
  }

  void _onReminderLater() {
    widget.onAction?.call('remind_later', 0);
    setState(() {
      _expandedReminderPart = null;
    });
    if (_state == IslandState.reminderSplit) {
      _resizeWithAnimation(_targetSizeFor(IslandState.reminderSplit));
    } else {
      _transitionToState(IslandState.reminderCapsule);
    }
  }

  Widget _buildReminderSplit() {
    final data = _reminderPopupData;
    if (data == null) return const SizedBox.shrink();

    final type = data['type']?.toString() ?? 'todo';
    final title = data['title']?.toString() ?? '';
    final minutesUntil = data['minutesUntil'] as int? ?? 0;

    final typeIcon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final statusText = '${minutesUntil}min';

    final isExpanded = _expandedReminderPart != null;

    final capsulesRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _startDragging(),
          onTap: () {
            if (isExpanded && _expandedReminderPart == 'focusing') {
              setState(() => _expandedReminderPart = null);
            } else {
              setState(() => _expandedReminderPart = 'focusing');
            }
            _resizeWithAnimation(_targetSizeFor(IslandState.reminderSplit));
          },
          child: _buildSplitFocusingCapsule(isExpanded: false),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _startDragging(),
          onTap: () {
            if (isExpanded && _expandedReminderPart == 'reminder') {
              setState(() => _expandedReminderPart = null);
            } else {
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
        key: const ValueKey('reminderSplit'),
        child: Center(child: capsulesRow),
      );
    }

    final expandedCard = _expandedReminderPart == 'focusing'
        ? _buildSplitFocusingExpanded()
        : _buildSplitReminderExpanded();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 46,
          child: Center(child: capsulesRow),
        ),
        Positioned(
          top: 46 + 8,
          left: 8,
          right: 8,
          child: expandedCard,
        ),
      ],
    );
  }

  Widget _buildSplitFocusingExpanded() {
    final focusData = _currentPayload?['focusData'] as Map?;
    final focusTitle = focusData?['title']?.toString() ?? '自由专注';
    final focusTags = (focusData?['tags'] as List?)?.join(' ') ?? '';

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
                  color: IslandConfig.successColor,
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
                  color: IslandConfig.dangerColor,
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
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IslandConfig.bgColor,
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
                  color: IslandConfig.successColor,
                  onTap: _onReminderOk,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDesignBtn(
                  label: '稍后提醒',
                  color: IslandConfig.warningColor,
                  onTap: _onReminderLater,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCapsule() {
    final data = _reminderPopupData;
    if (data == null) return const SizedBox.shrink();

    final type = data['type']?.toString() ?? 'todo';
    final title = data['title']?.toString() ?? '';
    final minutesUntil = data['minutesUntil'] as int? ?? 0;

    final typeIcon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final statusText = '${minutesUntil}min';

    return GestureDetector(
      key: const ValueKey('reminderCapsule'),
      onPanStart: (_) => _startDragging(),
      onTap: () {
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
            color: IslandConfig.warningColor.withOpacity(0.9),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(typeIcon, style: const TextStyle(fontSize: 12)),
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

  Widget _buildSplitFocusingCapsule({bool isExpanded = false}) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: IslandConfig.focusColor.withOpacity(0.9),
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

  Widget _buildSplitReminderCapsule(
      String typeIcon, String title, String statusText) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: IslandConfig.warningColor.withOpacity(0.9),
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
              color: IslandConfig.successColor,
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
      widget.onAction?.call('open_link', 0, url);
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
    _copiedLinkTimer = Timer(IslandConfig.copiedLinkDismissDuration, () {
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
          borderRadius: BorderRadius.circular(IslandConfig.miniButtonRadius),
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
          borderRadius: BorderRadius.circular(IslandConfig.buttonRadius),
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
