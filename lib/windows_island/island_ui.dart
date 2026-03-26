import 'package:flutter/material.dart';
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
  finishFinal // The "专注完成" state
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
  IslandState? _savedStateBeforeHover; // To return to focusing/idle after hover exit
  Map<String, dynamic>? _currentPayload;
  bool _isLocal = true;
  bool _isFocusing = false;

  double _width = 160;
  double _height = 36;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _splitController;

  Timer? _countdownTimer;
  int _remainingSecs = 0;
  String _timeLabel = '';
  bool _isCountdown = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _splitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _applyPayload(widget.initialPayload);
    widget.payloadNotifier?.addListener(_onNotifierPayload);
  }

  @override
  void dispose() {
    widget.payloadNotifier?.removeListener(_onNotifierPayload);
    _pulseController.dispose();
    _splitController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onNotifierPayload() {
    if (mounted) _applyPayload(widget.payloadNotifier!.value);
  }

  void _applyPayload(Map<String, dynamic>? payload) {
    if (payload == null) return;
    _currentPayload = payload;

    final focusData = payload['focusData'] as Map?;
    final String stateStr = payload['state']?.toString() ?? 'idle';
    
    // Detect focusing based on state string, endMs, or a non-empty time label
    // Check both local and remote (syncMode)
    final int endMs = focusData?['endMs'] ?? 0;
    final String timeLabel = focusData?['timeLabel']?.toString() ?? '';
    _isFocusing = stateStr == 'focusing' || endMs > 0 || timeLabel.isNotEmpty;

    setState(() {
      _isLocal = (focusData?['syncMode']?.toString() ?? 'local') == 'local';
      
      if (focusData != null) {
        _timeLabel = timeLabel.isNotEmpty ? timeLabel : _timeLabel;
        _isCountdown = focusData['isCountdown'] ?? true;
        _parseTimeLabel(timeLabel); // Reset remaining secs based on payload if possible
      }

      // Map incoming state to internal IslandState
      IslandState nextState = _state;
      switch (stateStr) {
        case 'idle':
          nextState = _isFocusing ? IslandState.focusing : IslandState.idle;
          break;
        case 'focusing':
          nextState = IslandState.focusing;
          break;
        case 'split_alert':
          nextState = IslandState.splitAlert;
          break;
        case 'stacked_card':
          nextState = IslandState.stackedCard;
          break;
        case 'finish_confirm':
          nextState = IslandState.finishConfirm;
          break;
        case 'abandon_confirm':
          nextState = IslandState.abandonConfirm;
          break;
        case 'finish_final':
          nextState = IslandState.finishFinal;
          break;
        default:
          nextState = _isFocusing ? IslandState.focusing : IslandState.idle;
      }

      if (nextState != _state) {
        // If we are currently in a hover-expanded state, don't immediately
        // transition back unless the new state is critical (focusing/alert)
        if (_state == IslandState.hoverWide && (nextState == IslandState.idle || nextState == IslandState.focusing)) {
          _savedStateBeforeHover = nextState;
        } else {
          _transitionToState(nextState);
        }
      }
    });

    // We always run the timer to update the idle system clock!
    _startTimer();
  }

  void _onHoverEnter() {
    if (_state == IslandState.idle || _state == IslandState.focusing) {
      _savedStateBeforeHover = _state;
      _transitionToState(IslandState.hoverWide);
    }
  }

  void _onHoverExit() {
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
        _remainingSecs = int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2]);
      }
    } catch (_) {}
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_isFocusing) {
          if (_isCountdown) {
            if (_remainingSecs > 0) _remainingSecs--;
          } else {
            _remainingSecs++;
          }
        }
        // If not focusing, the setState still triggers a rebuild and updates
        // _displayTime with the current system time.
      });
    });
  }

  String get _displayTime {
    if (_state == IslandState.idle || (_state == IslandState.hoverWide && !_isFocusing)) {
      final now = DateTime.now();
      final h = now.hour.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    
    final m = (_remainingSecs ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _transitionToState(IslandState nextState) async {
    final prevState = _state;
    final prevW = _width;
    final prevH = _height;

    // Determine new window size based on design screenshot
    double targetW = 120, targetH = 34;
    switch (nextState) {
      case IslandState.idle:
        targetW = 120; targetH = 34; // Black pill "12:15"
        break;
      case IslandState.focusing:
        targetW = 160; targetH = 34; // "专注事项 20:05"
        break;
      case IslandState.hoverWide:
        targetW = 380; targetH = 34; // Long pill with icons
        break;
      case IslandState.splitAlert:
        targetW = 300; targetH = 36; // Two pills side-by-side
        break;
      case IslandState.stackedCard:
        targetW = 280; targetH = 140; // Local focus detail
        break;
      case IslandState.finishConfirm:
      case IslandState.abandonConfirm:
      case IslandState.finishFinal:
        targetW = 260; targetH = 130;
        break;
    }

    setState(() {
      _state = nextState;
      _width = targetW;
      _height = targetH;
    });

    if (nextState == IslandState.splitAlert) _splitController.forward();
    else if (prevState == IslandState.splitAlert) _splitController.reverse();

    bool shrinking = (targetW < prevW) || (targetH < prevH);
    if (!shrinking) {
      try {
        final controller = await WindowController.fromCurrentEngine();
        await controller.invokeMethod('setWindowSize', {'width': targetW, 'height': targetH});
      } catch (_) {}
    } else {
      Future.delayed(const Duration(milliseconds: 400), () async {
        if (_state == nextState) {
          try {
            final controller = await WindowController.fromCurrentEngine();
            await controller.invokeMethod('setWindowSize', {'width': targetW, 'height': targetH});
          } catch (_) {}
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // FFI ColorKey is 0x000000, so any pure black would be invisible!
    // Using 0xFF010101 ensures it looks perfectly black to users but survives the FFI ColorKey.
    final bgColor = const Color(0xFF010101);
    final borderColor = Colors.white.withOpacity(0.15);

    return MouseRegion(
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverExit(),
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutQuart,
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(_state == IslandState.stackedCard || _state == IslandState.finishConfirm || _state == IslandState.abandonConfirm || _state == IslandState.finishFinal ? 20 : 28),
              border: Border.all(color: borderColor, width: 0.8),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_state == IslandState.stackedCard || _state == IslandState.finishConfirm || _state == IslandState.abandonConfirm || _state == IslandState.finishFinal ? 20 : 28),
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: _getContentForState(),
    );
  }

  Widget _getContentForState() {
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
        child: Text(
          _displayTime,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.0),
        ),
      ),
    );
  }

  Widget _buildFocusing() {
    final focusData = _currentPayload?['focusData'] as Map?;
    final title = focusData?['title']?.toString() ?? '专注事项';

    return GestureDetector(
      key: const ValueKey('focusing'),
      onTap: () => _transitionToState(_isLocal ? IslandState.splitAlert : IslandState.stackedCard),
      onPanStart: (_) => _startDragging(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
            Text(_displayTime, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _buildHoverWide() {
    final dashData = _currentPayload?['dashboardData'] as Map?;
    final left = dashData?['leftSlot']?.toString() ?? '';
    final right = dashData?['rightSlot']?.toString() ?? '';

    return GestureDetector(
      key: const ValueKey('hoverWide'),
      onTap: () => _transitionToState(IslandState.idle),
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
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _displayTime, // Real dynamic time
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                right,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
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
          // Left: Timer pill (matching design's specific padding and size)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20)),
            alignment: Alignment.center,
            child: Text(_displayTime, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 4),
          // Right: Content pill
          Expanded(
            child: GestureDetector(
              onTap: () => _transitionToState(IslandState.stackedCard),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Icon(iconData, color: Colors.white, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$reminderTitle ${reminderTime.isNotEmpty ? reminderTime : ""}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$_displayTime | $title', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(tags, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildDesignBtn(label: '完成', color: const Color(0xFF4CAF50), onTap: () => _transitionToState(IslandState.finishConfirm))),
              const SizedBox(width: 12),
              Expanded(child: _buildDesignBtn(label: '放弃', color: const Color(0xFFD32F2F), onTap: () => _transitionToState(IslandState.abandonConfirm))),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildConfirm({required String mode}) {
    String mainText = '';
    String subText = '专注内容 | 已专注时长';
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
    subText = '$title | $_displayTime';

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(mainText, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(subText, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (mode == 'final') 
            _buildDesignBtn(label: okLabel, color: okColor, onTap: () => _transitionToState(IslandState.idle))
          else
            Row(
              children: [
                if (!isReverse) ...[
                  Expanded(child: _buildDesignBtn(label: okLabel, color: okColor, onTap: () {
                    widget.onAction?.call(mode == 'finish' ? 'finish' : 'abandon', _remainingSecs);
                    _transitionToState(mode == 'finish' ? IslandState.finishFinal : IslandState.idle);
                  })),
                  const SizedBox(width: 12),
                  Expanded(child: _buildDesignBtn(label: cancelLabel, color: cancelColor, onTap: () => _transitionToState(IslandState.stackedCard))),
                ] else ...[
                  Expanded(child: _buildDesignBtn(label: cancelLabel, color: okColor, onTap: () => _transitionToState(IslandState.stackedCard))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildDesignBtn(label: okLabel, color: cancelColor, onTap: () {
                    widget.onAction?.call('abandon', 0);
                    _transitionToState(IslandState.idle);
                  })),
                ]
              ],
            )
        ],
      ),
    );
  }

  Widget _buildDesignBtn({required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
      ),
    );
  }


  void _startDragging() async {
    try {
      final controller = await WindowController.fromCurrentEngine();
      await controller.invokeMethod('startDragging');
    } catch (_) {}
  }
}
