part of '../thirty_day_challenge_screen.dart';

class _ChallengeTaskEditDialog extends StatefulWidget {
  final ThirtyDayChallengeTask task;

  const _ChallengeTaskEditDialog({required this.task});

  @override
  State<_ChallengeTaskEditDialog> createState() =>
      _ChallengeTaskEditDialogState();
}

class _ChallengeTaskEditDialogState extends State<_ChallengeTaskEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('调整第 ${widget.task.id} 项'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: '任务内容',
          hintText: widget.task.originalTitle,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('恢复原任务'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ShuffleCardStack extends StatefulWidget {
  final List<ThirtyDayChallengeTask> tasks;
  final Future<void> Function(ThirtyDayChallengeTask) onFinished;

  const _ShuffleCardStack({required this.tasks, required this.onFinished});

  @override
  State<_ShuffleCardStack> createState() => _ShuffleCardStackState();
}

class _ShuffleCardStackState extends State<_ShuffleCardStack>
    with SingleTickerProviderStateMixin {
  late final List<ThirtyDayChallengeTask> _sequence;
  late final AnimationController _controller;
  late final Animation<int> _stepAnimation;
  late final ValueNotifier<int> _stepNotifier;
  bool _hasNotified = false;

  @override
  void initState() {
    super.initState();
    _sequence = _buildSequence(widget.tasks);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    );
    _stepAnimation = IntTween(
      begin: 0,
      end: _sequence.length - 1,
    ).animate(_controller.drive(CurveTween(curve: Curves.easeInOutCubic)));
    _stepNotifier = ValueNotifier<int>(_stepAnimation.value);
    _controller.addListener(_updateStepNotifier);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_hasNotified) {
        _hasNotified = true;
        unawaited(widget.onFinished(_sequence.last));
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.removeListener(_updateStepNotifier);
    _stepNotifier.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _updateStepNotifier() {
    final step = _stepAnimation.value;
    if (_stepNotifier.value != step) _stepNotifier.value = step;
  }

  List<ThirtyDayChallengeTask> _buildSequence(
    List<ThirtyDayChallengeTask> tasks,
  ) {
    final pool = List<ThirtyDayChallengeTask>.of(tasks);
    final random = Random();
    final previewCount = min(6, max(1, pool.length));
    final sequence = [
      for (var index = 0; index < previewCount; index++)
        pool[random.nextInt(pool.length)],
    ];
    var finalTask = pool[random.nextInt(pool.length)];
    if (pool.length > 1 && finalTask.id == sequence.last.id) {
      finalTask = pool.firstWhere((task) => task.id != sequence.last.id);
    }
    sequence.add(finalTask);
    return sequence;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = min(
          constraints.maxHeight.isFinite ? constraints.maxHeight : 520.0,
          560.0,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: ValueListenableBuilder<int>(
              valueListenable: _stepNotifier,
              builder: (context, step, _) {
                final current = _sequence[step];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var layer = 3; layer >= 1; layer--)
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: layer * 10,
                            left: layer * 4,
                            right: layer * 4,
                          ),
                          child: Transform.scale(
                            scale: 1 - layer * 0.035,
                            alignment: Alignment.topCenter,
                            child: _ShuffleCardSurface(
                              task:
                                  _sequence[(step + layer) % _sequence.length],
                              isFront: false,
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                              fit: StackFit.expand,
                              children: [...previousChildren, ?currentChild],
                            ),
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, 0.8),
                            end: Offset.zero,
                          ).animate(animation);
                          return AnimatedBuilder(
                            animation: animation,
                            child: child,
                            builder: (context, child) {
                              if (animation.value <= 0.001) {
                                return const SizedBox.shrink();
                              }
                              if (animation.value >= 0.999) {
                                return child!;
                              }
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slide,
                                  child: ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        child: _ShuffleCardSurface(
                          key: ValueKey('${current.id}-$step'),
                          task: current,
                          isFront: true,
                        ),
                      ),
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
}

class _ShuffleCardSurface extends StatelessWidget {
  final ThirtyDayChallengeTask task;
  final bool isFront;

  const _ShuffleCardSurface({
    super.key,
    required this.task,
    required this.isFront,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCompact =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final taskColors = _challengeTaskGradientColors(task, scheme);
    final cardTextColor = isFront
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final colors = isFront
        ? taskColors
        : [
            Color.alphaBlend(
              taskColors.first.withValues(alpha: 0.18),
              scheme.surface,
            ),
            Color.alphaBlend(
              taskColors[1].withValues(alpha: 0.12),
              scheme.surface,
            ),
          ];
    return Container(
      padding: EdgeInsets.all(isCompact ? 18 : 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isFront
              ? taskColors.first.withValues(alpha: 0.62)
              : scheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isFront ? 0.12 : 0.05),
            blurRadius: isFront ? 24 : 12,
            offset: Offset(0, isFront ? 10 : 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '第 ${task.id} 项',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cardTextColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Icon(
                isFront ? Icons.auto_awesome_rounded : Icons.layers_rounded,
                color: scheme.primary,
              ),
            ],
          ),
          const Spacer(),
          Icon(
            isFront ? Icons.explore_rounded : Icons.style_rounded,
            size: isCompact ? 42 : 56,
            color: scheme.primary,
          ),
          SizedBox(height: isCompact ? 8 : 18),
          Text(
            isFront ? '正在寻找一项没做过的事' : '下一张体验',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: isCompact ? 6 : 12),
          Text(
            task.title,
            textAlign: TextAlign.center,
            style:
                (isCompact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                      color: cardTextColor,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
          ),
          const Spacer(),
          if (isFront)
            Text(
              '这项任务还没有完成，准备好了吗？',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: cardTextColor),
            ),
        ],
      ),
    );
  }
}

class _ChallengeTaskCard extends StatefulWidget {
  final ThirtyDayChallengeTask task;
  final ValueChanged<bool> onComplete;
  final Future<void> Function(String) onSaveFeeling;
  final VoidCallback onEdit;
  final VoidCallback? onStartFocus;
  final bool isImageLoading;
  final Future<void> Function() onPickImage;

  const _ChallengeTaskCard({
    required this.task,
    required this.onComplete,
    required this.onSaveFeeling,
    required this.onEdit,
    this.onStartFocus,
    required this.isImageLoading,
    required this.onPickImage,
  });

  @override
  State<_ChallengeTaskCard> createState() => _ChallengeTaskCardState();
}

final Map<String, Uint8List> _challengeImageMemoryCache = {};
const int _maxChallengeImageCacheEntries = 64;

Uint8List? _decodeChallengeImage(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  final cached = _challengeImageMemoryCache[encoded];
  if (cached != null) return cached;
  try {
    final decoded = base64Decode(encoded);
    if (_challengeImageMemoryCache.length >= _maxChallengeImageCacheEntries) {
      _challengeImageMemoryCache.remove(_challengeImageMemoryCache.keys.first);
    }
    _challengeImageMemoryCache[encoded] = decoded;
    return decoded;
  } catch (_) {
    return null;
  }
}

ImageProvider<Object>? _challengeImageProvider(
  String? encoded, {
  bool limitWindowsDecode = false,
}) {
  if (encoded == null || encoded.isEmpty) return null;
  try {
    if (AppPlatform.isWindows) {
      // Validate the base64 string without allocating another byte buffer on
      // every card rebuild. The provider key lets Flutter reuse its decode.
      final provider = Base64ImageProvider(base64.normalize(encoded));
      return limitWindowsDecode
          ? ResizeImage(
              provider,
              width: 2048,
              height: 2048,
              policy: ResizeImagePolicy.fit,
            )
          : provider;
    }

    final bytes = _decodeChallengeImage(encoded);
    if (bytes == null) return null;
    final provider = MemoryImage(bytes);
    return limitWindowsDecode
        ? ResizeImage.resizeIfNeeded(800, 800, provider)
        : provider;
  } catch (_) {
    return null;
  }
}

/// 为每项挑战分配一组有语义倾向的主题色：餐饮、交通、自然、社交、
/// 创作和情绪表达会使用不同的 Material 主题角色，再通过 HSL 提高饱和度，
/// 避免动态主题生成的浅灰色容器让卡片失去活力。
List<Color> _challengeTaskGradientColors(
  ThirtyDayChallengeTask task,
  ColorScheme scheme,
) {
  final starts = <Color>[
    scheme.secondary, // 餐厅
    scheme.primary, // 交通
    scheme.tertiary, // 老友
    scheme.primary, // 阅读
    scheme.secondary, // 离开网络
    scheme.tertiary, // 早餐
    scheme.tertiary, // 家人
    scheme.primary, // 饮料
    scheme.primary, // 电影
    scheme.secondary, // 跟点
    scheme.tertiary, // 写信
    scheme.secondary, // 手工
    scheme.tertiary, // 自然
    scheme.primary, // 陌生人
    scheme.tertiary, // 回忆
    scheme.secondary, // 整理
    scheme.primary, // 慢跑
    scheme.primary, // 早睡
    scheme.error, // 爱与表达
    scheme.tertiary, // 花
    scheme.secondary, // 野餐
    scheme.error, // 拒绝
    scheme.secondary, // KTV
    scheme.error, // 不加班
    scheme.primary, // 新朋友
    scheme.tertiary, // 礼物
    scheme.primary, // 过夜
    scheme.secondary, // 购物
    scheme.tertiary, // 妆容
    scheme.primary, // 总结
  ];
  final ends = <Color>[
    scheme.tertiary,
    scheme.secondary,
    scheme.primary,
    scheme.tertiary,
    scheme.primary,
    scheme.secondary,
    scheme.secondary,
    scheme.secondary,
    scheme.tertiary,
    scheme.tertiary,
    scheme.primary,
    scheme.tertiary,
    scheme.primary,
    scheme.secondary,
    scheme.primary,
    scheme.primary,
    scheme.tertiary,
    scheme.secondary,
    scheme.tertiary,
    scheme.secondary,
    scheme.tertiary,
    scheme.primary,
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
    scheme.secondary,
    scheme.tertiary,
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
  ];
  final hueShifts = <double>[
    16,
    -18,
    10,
    -8,
    24,
    -14,
    8,
    20,
    -12,
    14,
    -20,
    12,
    -10,
    18,
    -16,
    8,
    -14,
    18,
    0,
    -12,
    14,
    0,
    20,
    4,
    -18,
    12,
    -10,
    18,
    -14,
    8,
  ];
  final index = (task.id - 1).clamp(0, starts.length - 1).toInt();
  final shift = hueShifts[index];
  return [
    _vividChallengeColor(starts[index], scheme, hueShift: shift),
    _vividChallengeColor(ends[index], scheme, hueShift: shift - 8),
    _vividChallengeColor(starts[index], scheme, hueShift: shift + 10),
  ];
}

Color _vividChallengeColor(
  Color source,
  ColorScheme scheme, {
  double hueShift = 0,
}) {
  final hsl = HSLColor.fromColor(source);
  final hue = (hsl.hue + hueShift) % 360;

  final vibrantColor = HSLColor.fromAHSL(1, hue, 0.85, 0.5).toColor();
  final opacity = scheme.brightness == Brightness.dark ? 0.35 : 0.18;
  return Color.alphaBlend(
    vibrantColor.withValues(alpha: opacity),
    scheme.surface,
  );
}

class _ChallengeTaskCardState extends State<_ChallengeTaskCard> {
  late final TextEditingController _feelingController;
  bool _expanded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _feelingController = TextEditingController(text: widget.task.feeling);
  }

  @override
  void didUpdateWidget(covariant _ChallengeTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Keyboard visibility changes rebuild the parent, but they do not mean
    // that the task changed. Only replace the draft when this card starts
    // displaying a different task; otherwise an unsaved feeling gets reset to
    // the persisted value while the user is still editing it.
    if (!identical(oldWidget.task, widget.task)) {
      _feelingController.text = widget.task.feeling;
    }
  }

  @override
  void dispose() {
    _feelingController.dispose();
    super.dispose();
  }

  Future<void> _saveFeeling() async {
    setState(() => _saving = true);
    try {
      await widget.onSaveFeeling(_feelingController.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _expanded = false;
      });
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final task = widget.task;
    final isCompactMobile =
        MediaQuery.sizeOf(context).width < 600 &&
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final imageProvider = _challengeImageProvider(
      task.imageBase64,
      limitWindowsDecode: true,
    );
    final hasImage = imageProvider != null;
    final taskColors = _challengeTaskGradientColors(task, scheme);
    final cardColors = task.isCompleted
        ? [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.12),
              taskColors[0],
            ),
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.08),
              taskColors[1],
            ),
            taskColors[2],
          ]
        : taskColors;
    final cardForeground = hasImage ? Colors.white : scheme.onSurface;
    final mutedForeground = hasImage
        ? Colors.white.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final borderColor = task.isCompleted
        ? (hasImage
              ? Colors.white.withValues(alpha: 0.5)
              : taskColors.first.withValues(alpha: 0.66))
        : taskColors.first.withValues(alpha: 0.48);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasImage
              ? [
                  taskColors[0].withValues(alpha: 0.3),
                  taskColors[1].withValues(alpha: 0.18),
                  taskColors[2].withValues(alpha: 0.42),
                ]
              : cardColors,
        ),
        image: hasImage
            ? DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
              )
            : null,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: borderColor, width: task.isCompleted ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.15),
            blurRadius: AppPlatform.isAndroid ? 10 : 24,
            offset: AppPlatform.isAndroid
                ? const Offset(0, 4)
                : const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            if (hasImage)
              Positioned.fill(
                child: AppPlatform.isWindows
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.scrim.withValues(alpha: 0.4),
                              taskColors[1].withValues(alpha: 0.12),
                              scheme.scrim.withValues(alpha: 0.52),
                            ],
                          ),
                        ),
                      )
                    : BackdropFilter(
                        filter: AppImageFilters.blur5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                scheme.scrim.withValues(alpha: 0.4),
                                taskColors[1].withValues(alpha: 0.12),
                                scheme.scrim.withValues(alpha: 0.52),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : 450,
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => setState(() => _expanded = !_expanded),
                        borderRadius: BorderRadius.circular(32),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 32, 24, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: task.isCompleted
                                          ? scheme.primary
                                          : hasImage
                                          ? Colors.white.withValues(alpha: 0.25)
                                          : scheme.surface.withValues(
                                              alpha: 0.4,
                                            ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: hasImage && !task.isCompleted
                                          ? Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.5,
                                              ),
                                            )
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (task.isCompleted) ...[
                                          Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color: scheme.onPrimary,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          task.isCompleted
                                              ? '已完成'
                                              : 'DAY ${task.id}',
                                          style: TextStyle(
                                            color: task.isCompleted
                                                ? scheme.onPrimary
                                                : (hasImage
                                                      ? Colors.white
                                                      : scheme.onSurface),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      if (!task.isCompleted &&
                                          widget.onStartFocus != null) ...[
                                        IconButton(
                                          tooltip: '开始专注（完成自动打卡）',
                                          onPressed: widget.onStartFocus,
                                          icon: const Icon(
                                            Icons.timer_outlined,
                                          ),
                                          style: IconButton.styleFrom(
                                            backgroundColor: hasImage
                                                ? Colors.white.withValues(
                                                    alpha: 0.25,
                                                  )
                                                : scheme.surface.withValues(
                                                    alpha: 0.4,
                                                  ),
                                            foregroundColor: hasImage
                                                ? Colors.white
                                                : scheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      IconButton(
                                        tooltip: '调整任务',
                                        onPressed: widget.onEdit,
                                        icon: const Icon(
                                          Icons.edit_note_rounded,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor: hasImage
                                              ? Colors.white.withValues(
                                                  alpha: 0.25,
                                                )
                                              : scheme.surface.withValues(
                                                  alpha: 0.4,
                                                ),
                                          foregroundColor: hasImage
                                              ? Colors.white
                                              : scheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: task.imageBase64 == null
                                            ? '添加背景图'
                                            : '更换背景图',
                                        onPressed: widget.isImageLoading
                                            ? null
                                            : widget.onPickImage,
                                        style: IconButton.styleFrom(
                                          backgroundColor: hasImage
                                              ? Colors.white.withValues(
                                                  alpha: 0.25,
                                                )
                                              : scheme.surface.withValues(
                                                  alpha: 0.4,
                                                ),
                                          foregroundColor: hasImage
                                              ? Colors.white
                                              : scheme.onSurface,
                                        ),
                                        icon: widget.isImageLoading
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : Icon(
                                                task.imageBase64 == null
                                                    ? Icons
                                                          .add_photo_alternate_outlined
                                                    : Icons.image_outlined,
                                              ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Text(
                                task.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: isCompactMobile ? 22 : null,
                                      fontWeight: FontWeight.w900,
                                      color: cardForeground,
                                      height: 1.35,
                                      decoration: task.isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: mutedForeground,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (task.isCompleted)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hasImage
                                            ? Colors.white.withValues(
                                                alpha: 0.2,
                                              )
                                            : scheme.surface.withValues(
                                                alpha: 0.4,
                                              ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '完成于 ${_formatDate(task.completedAt)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: hasImage
                                                  ? Colors.white
                                                  : scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    )
                                  else
                                    Text(
                                      '点击下方展开 · 记录这次感受',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: mutedForeground,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  if (task.isCustomized)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hasImage
                                            ? Colors.white.withValues(
                                                alpha: 0.2,
                                              )
                                            : scheme.surface.withValues(
                                                alpha: 0.4,
                                              ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '已调整',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: hasImage
                                                  ? Colors.white
                                                  : scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (task.feeling.trim().isNotEmpty)
                        _buildFeelingPreview(context, task, scheme, hasImage),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _expanded
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  0,
                                  28,
                                  28,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Divider(
                                      color: hasImage
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : taskColors.first.withValues(
                                              alpha: 0.32,
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '记下这次的感受',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: mutedForeground,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _feelingController,
                                      minLines: 3,
                                      maxLines: 6,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      style: TextStyle(
                                        color: hasImage
                                            ? Colors.white
                                            : scheme.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '当时发生了什么？你有什么感觉？',
                                        hintStyle: TextStyle(
                                          color: hasImage
                                              ? Colors.white.withValues(
                                                  alpha: 0.6,
                                                )
                                              : null,
                                        ),
                                        filled: true,
                                        fillColor: hasImage
                                            ? Colors.white.withValues(
                                                alpha: 0.1,
                                              )
                                            : Color.alphaBlend(
                                                taskColors.first.withValues(
                                                  alpha: 0.12,
                                                ),
                                                scheme.surfaceContainerHighest,
                                              ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: hasImage
                                                ? Colors.transparent
                                                : scheme.outlineVariant,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: hasImage
                                                ? Colors.white.withValues(
                                                    alpha: 0.3,
                                                  )
                                                : scheme.outlineVariant,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: hasImage
                                                ? Colors.white
                                                : scheme.primary,
                                          ),
                                        ),
                                        alignLabelWithHint: true,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: _saving
                                              ? null
                                              : _saveFeeling,
                                          icon: _saving
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.bookmark_add_outlined,
                                                ),
                                          label: const Text('保存感受'),
                                          style: hasImage
                                              ? OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  side: BorderSide(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                )
                                              : null,
                                        ),
                                        const Spacer(),
                                        FilledButton.icon(
                                          onPressed: () => widget.onComplete(
                                            !task.isCompleted,
                                          ),
                                          icon: Icon(
                                            task.isCompleted
                                                ? Icons.undo_rounded
                                                : Icons.check_rounded,
                                          ),
                                          label: Text(
                                            task.isCompleted ? '撤销完成' : '完成打卡',
                                          ),
                                          style: hasImage
                                              ? FilledButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor: Colors.black,
                                                )
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 12),
                      if (!_expanded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: IconButton(
                            tooltip: '展开记录感受',
                            onPressed: () => setState(() => _expanded = true),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            color: mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '日期未知';
    return _challengeDateFormat('M月d日').format(date);
  }

  Widget _buildFeelingPreview(
    BuildContext context,
    ThirtyDayChallengeTask task,
    ColorScheme scheme,
    bool hasImage,
  ) {
    final foreground = hasImage ? Colors.white : scheme.onSurface;
    final taskColors = _challengeTaskGradientColors(task, scheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: hasImage
              ? scheme.scrim.withValues(alpha: 0.52)
              : Color.alphaBlend(
                  taskColors[1].withValues(alpha: 0.16),
                  scheme.surfaceContainerHighest,
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasImage
                ? scheme.onInverseSurface.withValues(alpha: 0.24)
                : taskColors.first.withValues(alpha: 0.36),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote_rounded, size: 20, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.feeling,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
