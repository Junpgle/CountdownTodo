part of '../thirty_day_challenge_screen.dart';

extension _ThirtyDayChallengeBoardExt on _ThirtyDayChallengeScreenState {
  Widget _buildBody(ThirtyDayChallengeState state) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return isLandscape ? _buildLandscapeBody(state) : _buildPortraitBody(state);
  }

  Widget _buildPortraitBody(ThirtyDayChallengeState state) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _buildHeader(state, isLandscape: false),
        ),
        Expanded(
          child: _showOverview
              ? _buildGridOverview(state)
              : _buildCardArea(state),
        ),
        if (!_showOverview)
          _isShuffling ? _buildShuffleFooter() : _buildPager(state),
      ],
    );
  }

  Widget _buildLandscapeBody(ThirtyDayChallengeState state) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidebarWidth = min(400.0, max(300.0, screenWidth * 0.35));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: sidebarWidth,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: _buildHeader(state, isLandscape: true),
              ),
              Expanded(
                child: _buildGridOverview(state, isLandscapeSidebar: true),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(32),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Column(
                children: [
                  Expanded(
                    child: _buildCardArea(state, isLandscapeDetail: true),
                  ),
                  _isShuffling ? _buildShuffleFooter() : _buildPager(state),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridOverview(
    ThirtyDayChallengeState state, {
    bool isLandscapeSidebar = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, isLandscapeSidebar ? 8 : 16, 16),
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<int>) {
          final id = key.value;
          final index = state.tasks.indexWhere((t) => t.id == id);
          return index != -1 ? index : null;
        }
        return null;
      },
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isLandscapeSidebar ? 4 : 5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: state.tasks.length,
      itemBuilder: (context, index) {
        final task = state.tasks[index];
        final isSelected = _currentIndex == index;
        final overviewImageProvider = task.isCompleted
            ? _challengeImageProvider(task.imageBase64)
            : null;
        final taskColors = _challengeTaskGradientColors(task, scheme);
        final overviewColors = task.isCompleted
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

        return RepaintBoundary(
          key: ValueKey<int>(task.id),
          child: InkWell(
            onTap: () {
              _mutateState(() {
                _currentIndex = index;
                if (!isLandscapeSidebar) {
                  _showOverview = false;
                }
              });
              if (!isLandscapeSidebar) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _pageController.hasClients) {
                    _pageController.jumpToPage(index);
                  }
                });
              } else {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: overviewColors,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? taskColors.first
                      : task.isCompleted
                      ? taskColors[1].withValues(alpha: 0.62)
                      : taskColors.first.withValues(alpha: 0.32),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (overviewImageProvider != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final pixelRatio =
                              MediaQuery.maybeDevicePixelRatioOf(context) ??
                              1.0;
                          final cacheWidth = (constraints.maxWidth * pixelRatio)
                              .ceil()
                              .clamp(1, 4096)
                              .toInt();
                          final cacheHeight =
                              (constraints.maxHeight * pixelRatio)
                                  .ceil()
                                  .clamp(1, 4096)
                                  .toInt();
                          final imageProvider = ResizeImage(
                            overviewImageProvider,
                            width: cacheWidth,
                            height: cacheHeight,
                            policy: ResizeImagePolicy.fit,
                          );
                          return Image(
                            image: imageProvider,
                            fit: BoxFit.cover,
                            opacity: const AlwaysStoppedAnimation<double>(0.4),
                          );
                        },
                      ),
                    ),
                  Center(
                    child: task.isCompleted
                        ? Icon(
                            Icons.check_rounded,
                            color: isSelected
                                ? scheme.primary
                                : scheme.secondary,
                            size: 24,
                          )
                        : Text(
                            '${task.id}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardArea(
    ThirtyDayChallengeState state, {
    bool isLandscapeDetail = false,
  }) {
    return _isShuffling
        ? _ShuffleCardStack(
            tasks: state.unfinishedTasks,
            onFinished: _finishShuffle,
          )
        : PageView.builder(
            controller: _pageController,
            itemCount: state.tasks.length,
            onPageChanged: (index) => _mutateState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final task = state.tasks[index];
              return Padding(
                padding: EdgeInsets.symmetric(
                  vertical: isLandscapeDetail ? 24 : 12,
                  horizontal: isLandscapeDetail ? 8 : 4,
                ),
                child: _ChallengeTaskCard(
                  task: task,
                  onComplete: (completed) => _setCompleted(task.id, completed),
                  onSaveFeeling: (feeling) => _saveFeeling(task.id, feeling),
                  onEdit: () => _editTask(task),
                  onStartFocus: () => _startTaskFocus(task),
                  isImageLoading: _imageTaskId == task.id,
                  onPickImage: () => _pickTaskImage(task),
                ),
              );
            },
          );
  }

  Widget _buildHeader(
    ThirtyDayChallengeState state, {
    bool isLandscape = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isCompactMobile =
        !isLandscape && MediaQuery.sizeOf(context).width < 600;
    final headerColors = [
      _vividChallengeColor(scheme.primary, scheme, hueShift: 6),
      _vividChallengeColor(scheme.secondary, scheme, hueShift: -10),
      _vividChallengeColor(scheme.tertiary, scheme, hueShift: 8),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: headerColors,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isCompleted
                          ? '挑战完成！'
                          : _isPaused
                          ? '挑战已暂停'
                          : '今天想做点不一样的事',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: isCompactMobile ? 17 : null,
                        fontWeight: FontWeight.w900,
                        color: scheme.onPrimaryContainer,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isPaused
                          ? '首页 Banner 已隐藏，记录仍然保留。'
                          : state.isBuiltIn
                          ? '左右滑动，找一件让生活重新有感觉的小事。'
                          : '左右滑动，按自己的节奏完成这一项挑战。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: isCompactMobile ? 12 : null,
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: state.isCompleted || _isShuffling
                        ? '挑战已完成'
                        : '随机一个任务',
                    onPressed: state.isCompleted || _isShuffling
                        ? null
                        : _showRandomTask,
                    icon: const Icon(Icons.shuffle_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surface.withValues(alpha: 0.35),
                      foregroundColor: scheme.onSurface,
                    ),
                  ),
                  if (!isLandscape) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _showOverview ? '查看详情' : '网格总览',
                      onPressed: () {
                        _mutateState(() {
                          _showOverview = !_showOverview;
                        });
                        if (!_showOverview) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && _pageController.hasClients) {
                              _pageController.jumpToPage(_currentIndex);
                            }
                          });
                        }
                      },
                      icon: Icon(
                        _showOverview
                            ? Icons.view_agenda_rounded
                            : Icons.grid_view_rounded,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surface.withValues(alpha: 0.35),
                        foregroundColor: scheme.onSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: state.progress),
                  duration: const Duration(milliseconds: 850),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 12,
                      value: value,
                      backgroundColor: scheme.surface.withValues(alpha: 0.6),
                      valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) {
                    if (animation.value <= 0.001) {
                      return const SizedBox.shrink();
                    }
                    if (animation.value >= 0.999) {
                      return child!;
                    }
                    return ScaleTransition(scale: animation, child: child);
                  },
                ),
                child: Text(
                  '${state.completedCount}/${state.tasks.length}',
                  key: ValueKey(state.completedCount),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _isExportingReport || _isShuffling
                      ? null
                      : () => _openPlanningSettings(state),
                  icon: Icon(
                    state.includeInPlanning
                        ? Icons.event_available_rounded
                        : Icons.calendar_view_day_rounded,
                  ),
                  label: Text(
                    state.includeInPlanning
                        ? '已接入规划 · ${AppTimeFormats.minuteOfDay(state.effectivePreferredStartMinute ?? (20 * 60))}'
                        : '容量与专注',
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isExportingReport || _isShuffling
                      ? null
                      : () => _shareChallengeTemplate(state),
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('分享挑战'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _isExportingReport
                      ? null
                      : () => _shareChallengeReport(state),
                  icon: _isExportingReport
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded),
                  label: Text(_isExportingReport ? '生成中…' : '导出并分享'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isExportingReport || _isShuffling
                      ? null
                      : _resetProgress,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('重置状态'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isExportingReport || _isShuffling
                      ? null
                      : _toggleChallengePause,
                  icon: Icon(
                    _isPaused
                        ? Icons.play_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                  ),
                  label: Text(_isPaused ? '恢复参与' : '暂停挑战'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isExportingReport || _isShuffling
                      ? null
                      : _abandonChallenge,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('放弃挑战'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPager(ThirtyDayChallengeState state) {
    final scheme = Theme.of(context).colorScheme;
    final currentTask = state.tasks[_currentIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: '上一项',
            onPressed: _currentIndex == 0 ? null : () => _goToPage(-1),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.25),
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
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                    );
                  },
                  child: Text(
                    '第 ${currentTask.id} 项 / ${state.tasks.length}',
                    key: ValueKey(currentTask.id),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: (currentTask.id) / state.tasks.length,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.tertiary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: '下一项',
            onPressed: _currentIndex == state.tasks.length - 1
                ? null
                : () => _goToPage(1),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildShuffleFooter() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: scheme.tertiary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '正在从未完成的任务中洗牌…',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeReportPoster(
    ThirtyDayChallengeState state,
    ColorScheme scheme,
  ) {
    final feelingCount = state.tasks
        .where((task) => task.feeling.trim().isNotEmpty)
        .length;
    final imageCount = state.tasks
        .where((task) => task.imageBase64?.isNotEmpty == true)
        .length;
    final reportDateFormat = AppTimeFormats.dateFormatter('yyyy年M月d日');
    final generatedAt = reportDateFormat.format(DateTime.now());
    final startedAt = reportDateFormat.format(state.startedAt);

    return Container(
      width: 1080,
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(56, 56, 56, 72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(46, 42, 46, 42),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer,
                  scheme.secondaryContainer,
                  scheme.tertiaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(36),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CountDownTodo · LIFE REPORT',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '我的「${state.challengeTitle}」',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '重新找回生活中的兴奋感',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${state.completedCount}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        height: 0.9,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 10, bottom: 5),
                      child: Text(
                        '/ ${state.tasks.length} 项完成',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.78,
                          ),
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 14,
                    value: state.progress,
                    backgroundColor: scheme.surface.withValues(alpha: 0.42),
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  '开始于 $startedAt  ·  生成于 $generatedAt',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.72),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            '我为自己留下了',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildReportMetric(
                scheme,
                value: '$feelingCount',
                label: '条感受',
                icon: Icons.format_quote_rounded,
              ),
              const SizedBox(width: 16),
              _buildReportMetric(
                scheme,
                value: '$imageCount',
                label: '张照片',
                icon: Icons.photo_library_outlined,
              ),
              const SizedBox(width: 16),
              _buildReportMetric(
                scheme,
                value: '${state.tasks.length}',
                label: '次尝试',
                icon: Icons.explore_outlined,
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text(
            '${state.tasks.length} 项挑战内容',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          ...state.tasks.map((task) => _buildChallengeReportTask(task, scheme)),
          const SizedBox(height: 28),
          Center(
            child: Text(
              '单调瓦解了时间，而新奇展开了时间。',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              '把自己重新放回生活里 · CountDownTodo',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportMetric(
    ColorScheme scheme, {
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Expanded(
      child: OptionalLiquidGlassCard(
        borderRadius: 24,
        highContrast: true,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        fallbackDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary, size: 30),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChallengeReportTask(
    ThirtyDayChallengeTask task,
    ColorScheme scheme,
  ) {
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
    final foreground = hasImage ? scheme.onInverseSurface : scheme.onSurface;
    final mutedForeground = hasImage
        ? scheme.onInverseSurface.withValues(alpha: 0.78)
        : scheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      constraints: const BoxConstraints(minHeight: 168),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasImage
              ? [
                  taskColors[0].withValues(alpha: 0.28),
                  taskColors[1].withValues(alpha: 0.16),
                  taskColors[2].withValues(alpha: 0.42),
                ]
              : cardColors,
        ),
        image: imageProvider == null
            ? null
            : DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: task.isCompleted
              ? (hasImage
                    ? scheme.onInverseSurface.withValues(alpha: 0.64)
                    : taskColors.first.withValues(alpha: 0.66))
              : taskColors.first.withValues(alpha: 0.42),
          width: task.isCompleted ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 28, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: task.isCompleted
                    ? scheme.primary
                    : (hasImage
                          ? scheme.scrim.withValues(alpha: 0.48)
                          : scheme.secondaryContainer),
                shape: BoxShape.circle,
              ),
              child: task.isCompleted
                  ? Icon(Icons.check_rounded, color: scheme.onPrimary, size: 32)
                  : Text(
                      '${task.id}',
                      style: TextStyle(
                        color: hasImage
                            ? scheme.onInverseSurface
                            : scheme.onSecondaryContainer,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    task.isCompleted
                        ? '已完成 · ${_formatReportDate(task.completedAt)}'
                        : '还没有完成',
                    style: TextStyle(
                      color: mutedForeground,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (task.feeling.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      decoration: BoxDecoration(
                        color: hasImage
                            ? scheme.scrim.withValues(alpha: 0.42)
                            : scheme.surfaceContainerHighest.withValues(
                                alpha: 0.78,
                              ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.format_quote_rounded,
                            size: 22,
                            color: foreground,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              task.feeling,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 19,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatReportDate(DateTime? date) {
    if (date == null) return '日期未知';
    return AppTimeFormats.dateFormatter('yyyy年M月d日').format(date);
  }
}
