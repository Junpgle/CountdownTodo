part of '../workbench_view.dart';

const LinearGradient _tagListFadeGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
  stops: [0, 0.16, 0.84, 1],
);
Rect? _cachedTagListFadeBounds;
Shader? _cachedTagListFadeShader;

Shader _resolveTagListFadeShader(Rect bounds) {
  if (_cachedTagListFadeBounds == bounds && _cachedTagListFadeShader != null) {
    return _cachedTagListFadeShader!;
  }
  _cachedTagListFadeBounds = bounds;
  return _cachedTagListFadeShader = _tagListFadeGradient.createShader(bounds);
}

extension _PomodoroWorkbenchLayoutExt on PomodoroWorkbenchState {
  Widget _buildWorkbenchTransition(Widget child, Animation<double> animation) {
    final slidePosition = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(animation);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        if (animation.value >= 0.999) {
          return child!;
        }
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slidePosition, child: child),
        );
      },
    );
  }

  Widget _buildLatestWorkbenchLayout(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (previousChildren.isNotEmpty) previousChildren.last,
        ?currentChild,
      ],
    );
  }

  Widget _buildPortraitLayout(
    bool isIdle,
    bool isFocusing,
    bool isRemoteWatching,
    Color contentColor,
  ) {
    return Column(
      key: const ValueKey('portrait_layout'),
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: _buildWorkbenchTransition,
            // A rapid phase change keeps only the latest outgoing layout.
            layoutBuilder: _buildLatestWorkbenchLayout,
            child: isIdle
                ? _buildIdleLayout(contentColor)
                : _buildActiveLayout(
                    isFocusing,
                    isRemoteWatching,
                    contentColor,
                  ),
          ),
        ),
      ],
    );
  }

  // 🚀 专注工作台骨架屏：模拟大圆环计时器和任务选择区
  Widget _buildSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.05);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // 顶部状态栏骨架
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 24,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // 计时器圆环骨架
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: baseColor, width: 8),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 120,
                height: 48,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          // 任务区域骨架
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 20),
          // 按钮骨架
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: baseColor,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 120,
                height: 50,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: baseColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(
    bool isIdle,
    bool isFocusing,
    bool isRemoteWatching,
    Color contentColor,
  ) {
    return Row(
      key: ValueKey(isIdle ? 'landscape_idle' : 'landscape_active'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left side: Timer + Mode Toggle
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildImmersiveTimerWidget(),
              // Move mode toggle below the timer in landscape when idle
              if (isIdle) ...[
                const SizedBox(height: 18),
                _buildModeToggle(modeSwitchKey: _landscapeModeSwitchKey),
                if (_communityStats != null) ...[
                  const SizedBox(height: 10),
                  _buildCommunityStatsBadge(),
                ],
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Right side: Info and Actions
        Expanded(
          flex: 5,
          child: isIdle
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            key: _landscapeSettingsKey,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: '设置',
                            onPressed: _showSettingsDialog,
                          ),
                          IconButton(
                            key: _landscapeTagsManagerKey,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.label_outline),
                            tooltip: '标签',
                            onPressed: _showTagsDialog,
                          ),
                          _buildSyncLinkButton(
                            serverConnKey: _landscapeServerConnKey,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Expanded(
                      flex: 3,
                      child: _buildIdleMiddle(
                        focusTagsKey: _landscapeFocusTagsKey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildActions(
                      isIdle,
                      isFocusing,
                      isRemoteWatching,
                      contentColor,
                      bindTodoKey: _landscapeBindTodoKey,
                    ),
                    const Spacer(),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTagsList(isRemoteWatching),
                      const SizedBox(height: 16),
                      WorkbenchTaskArea(
                        isIdle: false,
                        isFocusing: isFocusing,
                        isRemoteWatching: isRemoteWatching,
                        boundTodo: _boundTodo,
                        contentColor: contentColor,
                        bindKey: _landscapeActiveBindTodoKey,
                        onTap: () => _showBindTodoDialog(
                          isSwitching: _boundTodo != null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildNoteButton(contentColor),
                      const SizedBox(height: 32),
                      _buildActions(
                        isIdle,
                        isFocusing,
                        isRemoteWatching,
                        contentColor,
                        bindTodoKey: _landscapeActiveBindTodoKey,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    bool isIdle,
    bool isFocusing,
    bool isRemoteWatching,
    bool isLandscape,
  ) {
    final isGlobalLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return SizedBox(
      height: kToolbarHeight,
      child: Row(
        children: [
          AnimatedOpacity(
            opacity: (isFocusing || isRemoteWatching || isGlobalLandscape)
                ? 1.0
                : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !(isFocusing || isRemoteWatching || isGlobalLandscape),
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          const Spacer(),
          if (!isLandscape) ...[
            AnimatedOpacity(
              opacity: isIdle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !isIdle,
                child: Row(
                  children: [
                    IconButton(
                      key: _portraitSettingsKey,
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: '设置',
                      onPressed: _showSettingsDialog,
                    ),
                    IconButton(
                      key: _portraitTagsManagerKey,
                      icon: const Icon(Icons.label_outline),
                      tooltip: '标签',
                      onPressed: _showTagsDialog,
                    ),
                  ],
                ),
              ),
            ),
            _buildWSStatusIndicator(serverConnKey: _portraitServerConnKey),
          ],
        ],
      ),
    );
  }

  Widget _buildWSStatusIndicator({required GlobalKey serverConnKey}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mode toggle is intentionally moved below the timer; keep only the sync indicator here
        _buildSyncLinkButton(serverConnKey: serverConnKey),
      ],
    );
  }

  Widget _buildModeToggle({required GlobalKey modeSwitchKey}) {
    if (_phase != PomodoroPhase.idle) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SegmentedButton<TimerMode>(
              key: modeSwitchKey,
              segments: const [
                ButtonSegment(
                  value: TimerMode.countdown,
                  label: Text('倒计时', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: TimerMode.countUp,
                  label: Text('正计时', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {_settings.mode},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              onSelectionChanged: _strictWaitingForFlip
                  ? null
                  : (s) async {
                      _mutateState(() {
                        _settings.mode = s.first;
                        if (_settings.mode != TimerMode.countUp) {
                          _settings.strictFreeFocus = false;
                        }
                        _remainingSeconds = _settings.mode == TimerMode.countUp
                            ? 0
                            : _settings.focusMinutes * 60;
                      });
                      await PomodoroService.saveSettings(_settings);
                    },
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              if (_settings.mode == TimerMode.countUp &&
                  (AppPlatform.isAndroid || AppPlatform.isIOS))
                FilterChip(
                  avatar: Icon(
                    Icons.screen_lock_portrait_outlined,
                    size: 16,
                    color: _settings.strictFreeFocus
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: const Text('严格模式', style: TextStyle(fontSize: 12)),
                  selected: _settings.strictFreeFocus,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: _strictWaitingForFlip
                      ? null
                      : (value) async {
                          _mutateState(() => _settings.strictFreeFocus = value);
                          await PomodoroService.saveSettings(_settings);
                        },
                ),
              Tooltip(
                message: '专注期间隐藏 CountdownTodo 的其他提醒，并同步到当前在线的其他设备；Android 授权后还会打开系统勿扰。专注进度和结束提醒仍保留。',
                child: FilterChip(
                  avatar: Icon(
                    Icons.do_not_disturb_on_outlined,
                    size: 16,
                    color: _settings.doNotDisturbDuringFocus
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: const Text('专注勿扰', style: TextStyle(fontSize: 12)),
                  selected: _settings.doNotDisturbDuringFocus,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: _strictWaitingForFlip
                      ? null
                      : (value) async {
                          _mutateState(() {
                            _settings.doNotDisturbDuringFocus = value;
                          });
                          await PomodoroService.saveSettings(_settings);
                        },
                ),
              ),
            ],
          ),
          if (FocusDoNotDisturbService.supportsSystemDoNotDisturb &&
              _settings.doNotDisturbDuringFocus &&
              _systemDoNotDisturbAccess != true) ...[
            TextButton.icon(
              onPressed: () async {
                await FocusDoNotDisturbService.openSystemDoNotDisturbSettings();
                await _refreshSystemDoNotDisturbAccess();
              },
              icon: const Icon(Icons.settings_outlined, size: 14),
              label: const Text('授权系统勿扰', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncLinkButton({required GlobalKey serverConnKey}) {
    IconData icon;
    Color color;
    String message;

    switch (_syncConnState) {
      case SyncConnectionState.connected:
        icon = Icons.link_rounded;
        color = Theme.of(context).colorScheme.tertiary;
        message = '跨端同步已连接';
        break;
      case SyncConnectionState.connecting:
        icon = Icons.sync;
        color = Theme.of(context).colorScheme.secondary;
        message = '正在连接同步通道...';
        break;
      case SyncConnectionState.error:
      case SyncConnectionState.disconnected:
        icon = Icons.link_off_rounded;
        color = Theme.of(context).colorScheme.error;
        message = '同步连接已断开，点击重试';
    }

    return IconButton(
      key: serverConnKey,
      tooltip: message,
      visualDensity: MediaQuery.orientationOf(context) == Orientation.landscape
          ? VisualDensity.compact
          : VisualDensity.standard,
      onPressed: () {
        // 🚀 强制触发重连
        _syncService.manualReconnect();
        if (_syncConnState != SyncConnectionState.connected) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(
              content: Text('正在尝试重新连接同步服务器...'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
      icon: _syncConnState == SyncConnectionState.connecting
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, color: color),
    );
  }

  Future<void> _loadCommunityStats() async {
    final stats = await PomodoroService.getTodayCommunityStats();
    if (!mounted) return;
    if (stats?.avgSeconds != _communityStats?.avgSeconds) {
      _mutateState(() => _communityStats = stats);
    }
  }

  Widget _buildCommunityStatsBadge() {
    final stats = _communityStats;
    if (stats == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_rounded, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '今日全站人均专注 ${formatDurationChinese(stats.avgSeconds)}',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleLayout(Color contentColor) {
    return Column(
      key: const ValueKey('idle_workbench'),
      children: [
        const Spacer(flex: 2),
        _buildImmersiveTimerWidget(),
        // Place mode toggle under the timer in idle state (portrait)
        const SizedBox(height: 12),
        _buildModeToggle(modeSwitchKey: _portraitModeSwitchKey),
        if (_communityStats != null) ...[
          const SizedBox(height: 10),
          _buildCommunityStatsBadge(),
        ],
        const SizedBox(height: 8),
        Expanded(
          flex: 12,
          child: _buildIdleMiddle(focusTagsKey: _portraitFocusTagsKey),
        ),
        _buildActions(
          true,
          false,
          false,
          contentColor,
          bindTodoKey: _portraitBindTodoKey,
        ),
      ],
    );
  }

  Widget _buildActiveLayout(
    bool isFocusing,
    bool isRemoteWatching,
    Color contentColor,
  ) {
    return Column(
      key: const ValueKey('active_workbench'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildImmersiveTimerWidget(),
        const SizedBox(height: 16),
        _buildTagsList(isRemoteWatching),
        const SizedBox(height: 16),
        WorkbenchTaskArea(
          isIdle: false,
          isFocusing: isFocusing,
          isRemoteWatching: isRemoteWatching,
          boundTodo: _boundTodo,
          contentColor: contentColor,
          bindKey: _portraitActiveBindTodoKey,
          onTap: () => _showBindTodoDialog(isSwitching: _boundTodo != null),
        ),
        const SizedBox(height: 16),
        _buildNoteButton(contentColor),
        const SizedBox(height: 16),
        _buildActions(
          false,
          isFocusing,
          isRemoteWatching,
          contentColor,
          bindTodoKey: _portraitActiveBindTodoKey,
        ),
      ],
    );
  }

  Widget _buildNoteButton(Color contentColor) {
    return GestureDetector(
      onTap: _showNoteDialog,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentNote.isEmpty
                  ? Icons.edit_note_rounded
                  : Icons.note_rounded,
              size: 14,
              color: contentColor.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _currentNote.isEmpty ? '添加备注' : _currentNote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: contentColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImmersiveTimerWidget() {
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: _timerTickNotifier,
        builder: (context, _, _) {
          final isCountUp = _settings.mode == TimerMode.countUp;
          final isRemoteCountUp = _remoteState?.duration == 0;
          return ImmersiveTimer(
            phase: _phase,
            remainingSeconds: _remainingSeconds,
            focusMinutes: _settings.focusMinutes,
            breakMinutes: _settings.breakMinutes,
            currentCycle: _currentCycle,
            totalCycles: _settings.cycles,
            isCountUp: isCountUp,
            isRemoteCountUp: isRemoteCountUp,
            remoteState: _remoteState,
            isCompact: widget.isCompact,
            isPaused: _isPaused,
            pauseSeconds: _pauseElapsedSecs,
            isStrictMode: _isStrictFreeFocus,
            isStrictWaitingForFlip: _strictWaitingForFlip,
            strictSensorState: _strictSensorState,
          );
        },
      ),
    );
  }

  Widget _buildTagsList(bool isRemoteWatching) {
    if (isRemoteWatching) {
      if (_remoteTagNames.isEmpty) return const SizedBox.shrink();
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: _remoteTagNames
            .map(
              (n) => _SimpleTag(
                name: n,
                color: Theme.of(context).colorScheme.secondary,
              ),
            )
            .toList(),
      );
    }
    final activeTags = _tags
        .where((t) => _selectedTagUuids.contains(t.uuid))
        .toList();
    if (activeTags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: activeTags
          .map(
            (t) => _SimpleTag(
              name: t.name,
              color: AppColorUtils.parseHex(t.color),
            ),
          )
          .toList(),
    );
  }

  Widget _buildIdleMiddle({required GlobalKey focusTagsKey}) {
    if (_tags.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final minContentHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - 48)
                  .clamp(0.0, double.infinity)
                  .toDouble()
            : 0.0;
        final tagList = SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minContentHeight),
            child: Center(
              child: Wrap(
                key: focusTagsKey,
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _tags.map((tag) {
                  final selected = _selectedTagUuids.contains(tag.uuid);
                  final color = AppColorUtils.parseHex(tag.color);
                  return FilterChip(
                    label: Text(tag.name, style: const TextStyle(fontSize: 13)),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: color.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: selected ? color : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onSelected: (val) async {
                      _mutateState(() {
                        if (val) {
                          _selectedTagUuids.add(tag.uuid);
                        } else {
                          _selectedTagUuids.remove(tag.uuid);
                        }
                      });
                      await _persistIdleBoundTodo(_boundTodo);
                      _showLocalFloat();
                      if (_phase == PomodoroPhase.focusing) {
                        _syncService.sendUpdateTagsSignal(
                          _tags
                              .where((t) => _selectedTagUuids.contains(t.uuid))
                              .map((t) => t.name)
                              .toList(),
                        );
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        );
        return ValueListenableBuilder<bool>(
          valueListenable:
              AndroidWindowRenderingPolicy.disableShaderContentFade,
          child: tagList,
          builder: (context, disableFade, child) {
            if (disableFade) return child!;
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: _resolveTagListFadeShader,
              child: child,
            );
          },
        );
      },
    );
  }

  Widget _buildActions(
    bool isIdle,
    bool isFocusing,
    bool isRemoteWatching,
    Color contentColor, {
    required GlobalKey bindTodoKey,
  }) {
    final bool isPaused = _isPaused && _phase == PomodoroPhase.focusing;
    // debugPrint(
    //     '[BuildActions] _isPaused: $_isPaused, _phase: $_phase, isPaused: $isPaused, isFocusing: $isFocusing');
    return WorkbenchActions(
      isIdle: isIdle,
      isFocusing: isFocusing,
      isRemoteWatching: isRemoteWatching,
      isStrictMode: _isStrictFreeFocus,
      isStrictWaitingForFlip: _strictWaitingForFlip,
      phase: _phase,
      boundTodo: _boundTodo,
      bindKey: bindTodoKey,
      onShowBindTodo: _showBindTodoDialog,
      onStartFocus: _startFocus,
      onCancelStrictWaiting: _strictStartInFlight ? null : _cancelStrictWaiting,
      onFinishEarly: _finishEarly,
      onAbandonFocus: _abandonFocus,
      onPauseFocus: isPaused ? null : _pauseFocus,
      onShowPauseDialog: isPaused ? _resumeFocus : _showPauseDialog,
      onSkipBreak: () async {
        _ticker?.cancel();
        NotificationService.cancelNotification();
        NotificationService.cancelReminder(40002);
        await _persistIdleBoundTodo(_boundTodo);
        await _clearRunStateSilently();
        _mutateState(() {
          _phase = PomodoroPhase.idle;
          _currentCycle += 1;
          _remainingSeconds = _settings.mode == TimerMode.countUp
              ? 0
              : _settings.focusMinutes * 60;
          _isPaused = false;
          _pausedAtMs = 0;
          _accumulatedMs = 0;
        });
        widget.onPhaseChanged(_phase);
      },
      isCompact: widget.isCompact,
    );
  }
}

class _SimpleTag extends StatelessWidget {
  final String name;
  final Color color;
  const _SimpleTag({required this.name, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        '#$name',
        style: TextStyle(
          fontSize: 12,
          color: color.withValues(alpha: 0.7),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _PauseTimerText extends StatelessWidget {
  final int pauseStartMs;
  final ValueNotifier<int> tickListenable;

  const _PauseTimerText({
    required this.pauseStartMs,
    required this.tickListenable,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tickListenable,
      builder: (context, _, child) {
        final seconds =
            (DateTime.now().millisecondsSinceEpoch - pauseStartMs) ~/ 1000;
        return Text('暂停时长: ${formatTimerMMSS(seconds)}');
      },
    );
  }
}
