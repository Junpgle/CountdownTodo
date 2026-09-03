part of 'todo_chat_screen.dart';

class _StaggeredFadeSlide extends StatelessWidget {
  final Widget child;
  final Duration delay;

  const _StaggeredFadeSlide({
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final delayedValue = delay.inMilliseconds == 0
            ? value
            : ((value * (360 + delay.inMilliseconds) - delay.inMilliseconds) /
                    360)
                .clamp(0.0, 1.0);
        return Opacity(
          opacity: delayedValue,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - delayedValue)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  const _PressableScale({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.96 : (_hovered ? 1.03 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            borderRadius: widget.borderRadius,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _IridescentActionPanel extends StatefulWidget {
  final Widget child;
  final bool isDark;

  const _IridescentActionPanel({
    required this.child,
    required this.isDark,
  });

  @override
  State<_IridescentActionPanel> createState() => _IridescentActionPanelState();
}

class _IridescentActionPanelState extends State<_IridescentActionPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );
    PowerSaveModeService.enabledListenable.addListener(_syncAnimation);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (AndroidEnergyPolicy.shouldRunDecorativeMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat(
          count: AndroidEnergyPolicy.decorativeRepeatCount(androidCount: 2),
        );
      }
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    PowerSaveModeService.enabledListenable.removeListener(_syncAnimation);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            foregroundPainter: _IridescentBorderPainter(
              progress: _controller.value,
              isDark: widget.isDark,
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _IridescentBorderPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  const _IridescentBorderPainter({
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final center = rect.center;
    final borderRect = rect.deflate(2.0);
    final radius = BorderRadius.circular(18).toRRect(borderRect);
    final colors = <Color>[
      const Color(0xFF5EFCE8).withValues(alpha: isDark ? 0.88 : 0.82),
      const Color(0xFF736EFE).withValues(alpha: isDark ? 0.82 : 0.74),
      const Color(0xFFFF7CE5).withValues(alpha: isDark ? 0.90 : 0.78),
      const Color(0xFFFFF275).withValues(alpha: isDark ? 0.86 : 0.72),
      const Color(0xFF7CFF8A).withValues(alpha: isDark ? 0.84 : 0.70),
      const Color(0xFF5EFCE8).withValues(alpha: isDark ? 0.88 : 0.82),
    ];
    final shader = SweepGradient(
      colors: colors,
      stops: const [0, 0.18, 0.38, 0.58, 0.78, 1],
      transform: GradientRotation(progress * math.pi * 2),
    ).createShader(rect);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRRect(radius, glowPaint);

    for (var i = 0; i < 3; i++) {
      final wave = math.sin((progress * math.pi * 2) + i * 1.7);
      final drift = Offset(
        math.cos(progress * math.pi * 2 + i) * 0.8,
        math.sin(progress * math.pi * 2 + i * 1.3) * 0.8,
      );
      final rippleRect = Rect.fromCenter(
        center: center + drift,
        width: borderRect.width - (i * 1.2) + wave,
        height: borderRect.height - (i * 1.2) - wave,
      );
      final ripple = BorderRadius.circular(18.0 - i).toRRect(rippleRect);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = i == 0 ? 2.1 : 1.1
        ..shader = shader
        ..blendMode = BlendMode.srcOver;
      canvas.drawRRect(ripple, paint);
    }

    final sheenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: isDark ? 0.28 : 0.38);
    final highlightRect = borderRect.deflate(1.2).shift(
          Offset(
            math.cos(progress * math.pi * 2) * 0.7,
            math.sin(progress * math.pi * 2) * 0.7,
          ),
        );
    canvas.drawRRect(
        BorderRadius.circular(16).toRRect(highlightRect), sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _IridescentBorderPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

class _CollapsibleReasoningWidget extends StatefulWidget {
  final String reasoning;
  final bool isDark;
  final bool isStreaming;

  const _CollapsibleReasoningWidget({
    required this.reasoning,
    required this.isDark,
    required this.isStreaming,
  });

  @override
  State<_CollapsibleReasoningWidget> createState() =>
      _CollapsibleReasoningWidgetState();
}

class _CollapsibleReasoningWidgetState
    extends State<_CollapsibleReasoningWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.grey[900]!.withValues(alpha: 0.5)
            : Colors.grey[100]!.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (widget.isStreaming)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: MarkdownBody(
                data: widget.reasoning,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                  code: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                ),
                selectable: true,
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            firstCurve: Curves.easeInCubic,
            secondCurve: Curves.easeOutCubic,
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _PulseAvatar extends StatefulWidget {
  final Widget child;
  const _PulseAvatar({required this.child});
  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    PowerSaveModeService.enabledListenable.addListener(_syncAnimation);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (AndroidEnergyPolicy.shouldRunDecorativeMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat(
          reverse: true,
          count: AndroidEnergyPolicy.decorativeRepeatCount(),
        );
      }
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    PowerSaveModeService.enabledListenable.removeListener(_syncAnimation);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

class _ThinkingLoader extends StatefulWidget {
  const _ThinkingLoader();
  @override
  State<_ThinkingLoader> createState() => _ThinkingLoaderState();
}

class _ThinkingLoaderState extends State<_ThinkingLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    PowerSaveModeService.enabledListenable.addListener(_syncAnimation);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (AndroidEnergyPolicy.shouldRunDecorativeMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    PowerSaveModeService.enabledListenable.removeListener(_syncAnimation);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset = (i * 0.2);
                double value = (_controller.value + offset) % 1.0;
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(
                      alpha: 0.2 + (0.8 * (1.0 - (value - 0.5).abs() * 2)),
                    ),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
          const SizedBox(width: 10),
          Text(
            '正在思考',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DanmakuSuggestions extends StatefulWidget {
  final List<String> suggestions;
  final Function(String) onTap;

  const _DanmakuSuggestions({
    required this.suggestions,
    required this.onTap,
  });

  @override
  State<_DanmakuSuggestions> createState() => _DanmakuSuggestionsState();
}

class _DanmakuSuggestionsState extends State<_DanmakuSuggestions>
    with WidgetsBindingObserver {
  late ScrollController _scrollCtrl1;
  late ScrollController _scrollCtrl2;
  late ScrollController _scrollCtrl3;
  Timer? _timer;
  bool _appInForeground = true;
  bool _tickerModeEnabled = false;

  bool get _shouldScroll =>
      mounted &&
      _appInForeground &&
      _tickerModeEnabled &&
      AndroidEnergyPolicy.shouldRunDecorativeMotion &&
      widget.suggestions.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PowerSaveModeService.enabledListenable
        .addListener(_syncScrollingWithVisibility);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appInForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _scrollCtrl1 = ScrollController();
    _scrollCtrl2 = ScrollController();
    _scrollCtrl3 = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScrollingWithVisibility();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    if (_tickerModeEnabled == tickerModeEnabled) return;
    _tickerModeEnabled = tickerModeEnabled;
    _syncScrollingWithVisibility();
  }

  @override
  void didUpdateWidget(covariant _DanmakuSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suggestions.isEmpty != widget.suggestions.isEmpty) {
      _syncScrollingWithVisibility();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _syncScrollingWithVisibility();
  }

  void _syncScrollingWithVisibility() {
    if (_shouldScroll) {
      _scheduleScrollTick(Duration.zero);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _scheduleScrollTick(Duration delay) {
    if (!_shouldScroll || _timer != null) return;
    _timer = Timer(delay, _handleScrollTick);
  }

  void _handleScrollTick() {
    _timer = null;
    if (!_shouldScroll) return;

    final scrollInterval = AndroidEnergyPolicy.decorativeScrollInterval(
      const Duration(milliseconds: 50),
    );
    // Distances scale with the interval so Android halves timer wakeups while
    // preserving the original pixels-per-second speed.
    final intervalScale = scrollInterval.inMicroseconds /
        const Duration(milliseconds: 30).inMicroseconds;
    final moved1 = _autoScroll(_scrollCtrl1, 0.35 * intervalScale);
    final moved2 = _autoScroll(_scrollCtrl2, 0.55 * intervalScale);
    final moved3 = _autoScroll(_scrollCtrl3, 0.45 * intervalScale);
    final moved = moved1 || moved2 || moved3;
    _scheduleScrollTick(
      moved ? scrollInterval : const Duration(seconds: 1),
    );
  }

  bool _autoScroll(ScrollController ctrl, double distance) {
    if (ctrl.hasClients) {
      final max = ctrl.position.maxScrollExtent;
      if (max > 0) {
        final next = ctrl.offset + distance;
        if (next >= max) {
          ctrl.jumpTo(0);
        } else {
          ctrl.jumpTo(next);
        }
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PowerSaveModeService.enabledListenable
        .removeListener(_syncScrollingWithVisibility);
    _timer?.cancel();
    _scrollCtrl1.dispose();
    _scrollCtrl2.dispose();
    _scrollCtrl3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) return const SizedBox.shrink();

    // 分成三行
    final row1 = <String>[];
    final row2 = <String>[];
    final row3 = <String>[];

    for (int i = 0; i < widget.suggestions.length; i++) {
      if (i % 3 == 0) {
        row1.add(widget.suggestions[i]);
      } else if (i % 3 == 1) {
        row2.add(widget.suggestions[i]);
      } else {
        row3.add(widget.suggestions[i]);
      }
    }

    // 为了实现无缝循环，每行内容加倍
    final items1 = [...row1, ...row1, ...row1];
    final items2 = [...row2, ...row2, ...row2];
    final items3 = [...row3, ...row3, ...row3];

    return Column(
      children: [
        if (row1.isNotEmpty) _buildRow(_scrollCtrl1, items1),
        if (row2.isNotEmpty) const SizedBox(height: 10),
        if (row2.isNotEmpty) _buildRow(_scrollCtrl2, items2),
        if (row3.isNotEmpty) const SizedBox(height: 10),
        if (row3.isNotEmpty) _buildRow(_scrollCtrl3, items3),
      ],
    );
  }

  Widget _buildRow(ScrollController ctrl, List<String> items) {
    return Expanded(
      child: ListView.builder(
        controller: ctrl,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _DanmakuItem(
              text: items[index],
              onTap: () => widget.onTap(items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _DanmakuItem extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _DanmakuItem({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
