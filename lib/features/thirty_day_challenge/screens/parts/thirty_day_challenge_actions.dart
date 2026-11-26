part of '../thirty_day_challenge_screen.dart';

extension _ThirtyDayChallengeActionsExt on _ThirtyDayChallengeScreenState {
  Future<void> _load() async {
    final state = widget.showBuiltInIntroduction
        ? ThirtyDayChallengeState.initial()
        : await ThirtyDayChallengeRepository.load();
    final introSeen = widget.showBuiltInIntroduction
        ? false
        : await ThirtyDayChallengeRepository.hasSeenIntro();
    final isPaused = widget.showBuiltInIntroduction
        ? false
        : await ThirtyDayChallengeRepository.isPaused();
    final hasCorruptBackup =
        !widget.showBuiltInIntroduction &&
        await ThirtyDayChallengeRepository.getCorruptStateBackup() != null;
    if (!mounted) return;
    _mutateState(() {
      _state = state;
      _showWelcome = !introSeen;
      _isPaused = isPaused;
    });
    _entranceController.forward();
    if (hasCorruptBackup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text('旧挑战记录无法读取，原始副本已保留。请在“数据导出”中备份“30 天挑战”数据。'),
          ),
        );
      });
    }
  }

  Future<void> _openNewChallenge() async {
    if (_isShuffling || _isExportingReport) return;

    final draft = await Navigator.of(context).push<ChallengeDraft>(
      MaterialPageRoute(builder: (_) => const NewChallengeScreen()),
    );
    if (draft == null || !mounted) return;

    await _startNewChallenge(draft);
  }

  Future<void> _startNewChallenge(ChallengeDraft draft) async {
    if (!mounted) return;

    final hasExistingChallenge = widget.showBuiltInIntroduction
        ? await ThirtyDayChallengeRepository.hasStarted()
        : false;
    if (!mounted) return;
    if (!_showWelcome || hasExistingChallenge) {
      final currentState = hasExistingChallenge
          ? await ThirtyDayChallengeRepository.load()
          : _state;
      if (!mounted) return;
      final shouldReplace = await AppDialogs.confirm(
        context,
        icon: const Icon(Icons.auto_awesome_rounded),
        title: '开启新的挑战？',
        message:
            '当前正在进行「${currentState?.challengeTitle ?? '当前挑战'}」。开始新挑战后，当前挑战的完成状态、感受和图片将被替换，无法恢复。',
        cancelLabel: '继续当前挑战',
        confirmLabel: '开启新挑战',
      );
      if (!shouldReplace || !mounted) return;
    }

    try {
      final state = await ThirtyDayChallengeRepository.startNewChallenge(
        title: draft.title,
        taskTitles: draft.taskTitles,
      );
      if (!mounted) return;
      _mutateState(() {
        _state = state;
        _showWelcome = false;
        _showOverview = false;
        _isPaused = false;
        _currentIndex = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('已开启「${state.challengeTitle}」')),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('新挑战创建失败，请稍后再试')),
      );
    }
  }

  Future<void> _enterChallenge() async {
    final challengeTitle =
        _state?.challengeTitle ?? ThirtyDayChallengeState.defaultTitle;
    final shouldStart = await AppDialogs.confirm(
      context,
      icon: Icon(
        Icons.cloud_off_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: '本活动仅保存在当前设备',
      message: '“$challengeTitle”目前不支持跨端同步。完成状态、任务调整、感受和图片记录只会保存在当前设备。',
      cancelLabel: '暂不开始',
      confirmLabel: '知道了，开始挑战',
    );
    if (!shouldStart || !mounted) return;

    try {
      if (widget.showBuiltInIntroduction) {
        final hasExistingChallenge =
            await ThirtyDayChallengeRepository.hasStarted();
        if (!mounted) return;
        if (hasExistingChallenge) {
          final currentState = await ThirtyDayChallengeRepository.load();
          if (!mounted) return;
          final shouldReplace = await AppDialogs.confirm(
            context,
            icon: const Icon(Icons.auto_awesome_rounded),
            title: '开始经典挑战？',
            message:
                '当前正在进行「${currentState.challengeTitle}」。开始经典挑战后，当前挑战的完成状态、感受和图片将被替换，无法恢复。',
            cancelLabel: '继续当前挑战',
            confirmLabel: '开始经典挑战',
          );
          if (!shouldReplace || !mounted) return;
        }

        final state =
            await ThirtyDayChallengeRepository.startBuiltInChallenge();
        if (!mounted) return;
        _mutateState(() {
          _state = state;
          _showWelcome = false;
          _showOverview = false;
          _isPaused = false;
          _currentIndex = 0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        });
        return;
      }

      await ThirtyDayChallengeRepository.markIntroSeen();
      if (!mounted) return;
      _mutateState(() {
        _showWelcome = false;
        _isPaused = false;
      });
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('欢迎页保存失败，请稍后再试')),
      );
    }
  }

  Future<void> _deferChallenge() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('可以稍后从帮助与反馈再次进入挑战')),
      );
    }
  }

  Future<void> _toggleChallengePause() async {
    if (_isShuffling) return;
    final nextPaused = !_isPaused;
    try {
      await ThirtyDayChallengeRepository.setPaused(nextPaused);
      if (!mounted) return;
      _mutateState(() => _isPaused = nextPaused);
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            nextPaused ? '已暂停首页活动 Banner，记录仍然保留' : '已恢复参与，首页 Banner 已显示',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('操作失败，请稍后再试')),
      );
    }
  }

  Future<void> _abandonChallenge() async {
    if (_isShuffling) return;

    final state = _state;
    final taskCount = state?.tasks.length ?? 0;
    final challengeTitle =
        state?.challengeTitle ?? ThirtyDayChallengeState.defaultTitle;

    final shouldAbandon = await AppDialogs.confirm(
      context,
      icon: Icon(
        Icons.delete_sweep_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: '放弃「$challengeTitle」？',
      message: '放弃后会清空 $taskCount 项任务的完成状态、任务调整、感受和图片记录，之后可以重新开始。此操作无法恢复。',
      cancelLabel: '继续挑战',
      confirmLabel: '放弃并清空',
      destructive: true,
    );
    if (!shouldAbandon) return;

    try {
      await ThirtyDayChallengeRepository.abandonChallenge();
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        _mutateState(() {
          _state = ThirtyDayChallengeState.initial();
          _showWelcome = true;
          _isPaused = false;
          _currentIndex = 0;
        });
      }
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('放弃失败，请稍后再试')),
      );
    }
  }

  Future<void> _resetProgress() async {
    final state = _state;
    if (state == null || _isShuffling) return;

    final shouldReset = await AppDialogs.confirm(
      context,
      icon: const Icon(Icons.restart_alt_rounded),
      title: '重置全部打卡状态？',
      message: '这会清除 ${state.tasks.length} 项任务的完成标记和完成时间，但会保留你调整过的任务、感受和图片记录。',
      confirmLabel: '重置状态',
    );
    if (!shouldReset || !mounted) return;

    try {
      await ThirtyDayChallengeRepository.resetProgress(state);
      if (!mounted) return;
      _mutateState(() => _currentIndex = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('已重置全部打卡状态，记录内容仍然保留')),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('重置失败，请稍后再试')),
      );
    }
  }

  Future<void> _shareChallengeReport(ThirtyDayChallengeState state) async {
    if (_isExportingReport) return;

    _mutateState(() => _isExportingReport = true);
    final posterKey = GlobalKey();
    OverlayEntry? entry;

    try {
      final overlay = Overlay.of(context);
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.01,
              child: Material(
                color: Colors.transparent,
                child: RepaintBoundary(
                  key: posterKey,
                  child: Theme(
                    data: theme,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        size: Size(1080, 1920),
                        devicePixelRatio: 1,
                        textScaler: TextScaler.noScaling,
                      ),
                      child: _buildChallengeReportPoster(state, colorScheme),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(entry);
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final boundary =
          posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('报告长图渲染失败');
      }

      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('报告长图编码失败');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final timestamp = AppTimeFormats.fileTimestamp(DateTime.now());
      final fileName =
          'CountDownTodo_${_safeFileName(state.challengeTitle)}_$timestamp.png';
      if (!kIsWeb) {
        await BrowserFileService.saveBytesFile(
          pngBytes,
          fileName,
          mimeType: 'image/png',
        );
      }
      await BrowserFileService.shareBytesFile(
        pngBytes,
        fileName,
        mimeType: 'image/png',
        text:
            '我的「${state.challengeTitle}」报告\n#${_safeHashTag(state.challengeTitle)} #打卡挑战 #CountDownTodo',
      );

      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text(kIsWeb ? '报告长图已下载' : '报告长图已生成，已打开分享面板')),
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('报告长图生成失败：$error')),
      );
    } finally {
      entry?.remove();
      if (mounted) _mutateState(() => _isExportingReport = false);
    }
  }

  Future<void> _shareChallengeTemplate(ThirtyDayChallengeState state) async {
    final tasks = state.tasks
        .map((task) => task.title.trim())
        .where((task) => task.isNotEmpty)
        .toList(growable: false);
    if (tasks.isEmpty) return;

    try {
      final sharedText = ChallengeShareCodec.encode(
        ChallengeDraft(title: state.challengeTitle, taskTitles: tasks),
      );
      await Clipboard.setData(ClipboardData(text: sharedText));
      await ClipboardSharePayload.markLocallyGenerated(sharedText);
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('已复制挑战分享内容，朋友可通过剪贴板识别并导入')),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('分享内容复制失败，请稍后再试')),
      );
    }
  }

  Future<void> _setCompleted(int taskId, bool completed) async {
    final state = _state;
    if (state == null) return;

    try {
      await ThirtyDayChallengeRepository.setCompleted(state, taskId, completed);
      if (!mounted) return;
      _mutateState(() {});
      if (completed) {
        final message = state.isCompleted
            ? '${state.tasks.length} 项挑战全部完成了，恭喜你遇见新的自己！'
            : '已完成 ${state.completedCount}/${state.tasks.length}，继续感受生活吧';
        AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('保存失败，请稍后再试')),
      );
    }
  }

  Future<void> _saveFeeling(int taskId, String feeling) async {
    final state = _state;
    if (state == null) return;

    try {
      await ThirtyDayChallengeRepository.updateTask(
        state,
        taskId,
        feeling: feeling,
      );
      if (mounted) _mutateState(() {});
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('感受保存失败，请稍后再试')),
      );
    }
  }

  Future<void> _pickTaskImage(ThirtyDayChallengeTask task) async {
    if (_imageTaskId != null) return;
    final state = _state;
    if (state == null) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    _mutateState(() => _imageTaskId = task.id);
    try {
      final originalBytes = await picked.readAsBytes();
      if (originalBytes.isEmpty) throw Exception('empty image');

      Uint8List compressedBytes;
      try {
        compressedBytes = await FlutterImageCompress.compressWithList(
          originalBytes,
          minWidth: 1200,
          minHeight: 1200,
          quality: 74,
          format: CompressFormat.jpeg,
        );
      } catch (_) {
        // 某些桌面平台可能没有压缩插件实现；ImagePicker 的质量和尺寸参数
        // 仍然会先做一次压缩，此处保留可用图片作为降级路径。
        compressedBytes = originalBytes;
      }

      await ThirtyDayChallengeRepository.updateTask(
        state,
        task.id,
        imageBase64: base64Encode(compressedBytes),
      );
      if (mounted) _mutateState(() {});
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('图片保存失败，请重新选择')),
      );
    } finally {
      if (mounted) _mutateState(() => _imageTaskId = null);
    }
  }

  Future<void> _editTask(ThirtyDayChallengeTask task) async {
    final editedTitle = await showAppDialog<String>(
      context: context,
      builder: (_) => _ChallengeTaskEditDialog(task: task),
    );

    if (editedTitle == null || !mounted) return;
    await ThirtyDayChallengeRepository.updateTask(
      _state!,
      task.id,
      customTitle: editedTitle,
    );
    if (mounted) _mutateState(() {});
  }

  Future<void> _startTaskFocus(ThirtyDayChallengeTask task) async {
    final state = _state;
    if (state == null || _isShuffling) return;
    final username = (await StorageService.getLoginSession() ?? '').trim();
    if (!mounted) return;
    await HabitFocusLauncher.openForChallenge(
      context: context,
      challengeState: state,
      task: task,
      username: username,
    );
    if (!mounted) return;
    final refreshed = await ThirtyDayChallengeRepository.load();
    if (!mounted) return;
    _mutateState(() => _state = refreshed);
  }

  Future<void> _openPlanningSettings(ThirtyDayChallengeState state) async {
    final tags = (await PomodoroService.getTags())
        .where((t) => !t.isDeleted && !t.isArchived)
        .toList();
    if (!mounted) return;

    var includeInPlanning = state.includeInPlanning;
    var preferredMinute = state.effectivePreferredStartMinute ?? (20 * 60);
    var plannedMinutes = state.effectivePlannedMinutes;
    final selectedTagUuids = List<String>.from(state.focusTagUuids);
    var autoCompleteOnFocus = state.autoCompleteOnFocus;

    final saved = await showAppModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final scheme = Theme.of(context).colorScheme;
            final timeText = AppTimeFormats.minuteOfDay(preferredMinute);

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_view_day_rounded,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '今日容量与专注联动',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '将 30 天挑战接入「今日容量与日程规划块」，每天自动为下一项未完成挑战预留专属时段，并支持一键开启番茄钟专注。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LiquidGlassSwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('纳入今日容量与规划块'),
                      subtitle: const Text('当天尚未完成挑战时，自动在日程时间轴预留软时间块'),
                      value: includeInPlanning,
                      onChanged: (v) =>
                          setModalState(() => includeInPlanning = v),
                    ),
                    if (includeInPlanning) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '偏好执行时段',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final picked = await showAppTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: (preferredMinute ~/ 60) % 24,
                                  minute: preferredMinute % 60,
                                ),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  preferredMinute =
                                      picked.hour * 60 + picked.minute;
                                });
                              }
                            },
                            icon: const Icon(Icons.schedule_rounded, size: 16),
                            label: Text(timeText),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '预计专注耗时（分钟）',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [15, 25, 30, 45, 60].map((minutes) {
                        return ChoiceChip(
                          label: Text('$minutes 分钟'),
                          selected: plannedMinutes == minutes,
                          onSelected: (_) =>
                              setModalState(() => plannedMinutes = minutes),
                        );
                      }).toList(),
                    ),
                    const Divider(height: 24),
                    LiquidGlassSwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('专注完成后自动打卡'),
                      subtitle: const Text('完成专注计时后自动将当前挑战任务标记为已完成'),
                      value: autoCompleteOnFocus,
                      onChanged: (v) =>
                          setModalState(() => autoCompleteOnFocus = v),
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '关联专注标签（可选）',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tags.map((tag) {
                          final selected = selectedTagUuids.contains(tag.uuid);
                          return FilterChip(
                            avatar: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColorUtils.parseHex(tag.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            label: Text(tag.name),
                            selected: selected,
                            onSelected: (v) {
                              setModalState(() {
                                if (v) {
                                  selectedTagUuids.add(tag.uuid);
                                } else {
                                  selectedTagUuids.remove(tag.uuid);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text('保存设置'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;
    await ThirtyDayChallengeRepository.updatePlanningConfig(
      state,
      includeInPlanning: includeInPlanning,
      preferredStartMinute: preferredMinute,
      plannedDurationMinutes: plannedMinutes,
      focusTagUuids: selectedTagUuids,
      autoCompleteOnFocus: autoCompleteOnFocus,
    );
    if (!mounted) return;
    _mutateState(() {});
    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: Text(
          includeInPlanning ? '已将 30 天挑战接入今日容量与规划块' : '已更新 30 天挑战专注设置',
        ),
      ),
    );
  }

  Future<void> _showRandomTask() async {
    final state = _state;
    if (state == null) return;

    final task = state.randomUnfinishedTask();
    if (task == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('所有任务都完成了，去回味一下你的记录吧')),
      );
      return;
    }

    if (!mounted) return;
    _mutateState(() => _isShuffling = true);
  }

  Future<void> _finishShuffle(ThirtyDayChallengeTask task) async {
    final state = _state;
    if (state == null || !mounted) return;
    final taskIndex = state.tasks.indexOf(task);
    if (taskIndex < 0) return;

    _mutateState(() {
      _isShuffling = false;
      _currentIndex = taskIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(taskIndex);
    });
  }

  Future<void> _goToPage(int offset) async {
    final state = _state;
    if (state == null || state.tasks.isEmpty) return;
    final nextIndex = (_currentIndex + offset)
        .clamp(0, state.tasks.length - 1)
        .toInt();
    if (nextIndex == _currentIndex) return;
    await _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }
}
