part of 'home_dashboard.dart';

// ignore_for_file: annotate_overrides

const LinearGradient _wallpaperTopFadeGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0.0, 0.18, 0.78, 1.0],
  colors: [Colors.white, Colors.white, Color(0x24FFFFFF), Colors.transparent],
);
Rect? _cachedWallpaperFadeBounds;
Shader? _cachedWallpaperFadeShader;

Shader _resolveWallpaperTopFadeShader(Rect bounds) {
  if (_cachedWallpaperFadeBounds == bounds &&
      _cachedWallpaperFadeShader != null) {
    return _cachedWallpaperFadeShader!;
  }
  _cachedWallpaperFadeBounds = bounds;
  return _cachedWallpaperFadeShader = _wallpaperTopFadeGradient.createShader(
    bounds,
  );
}

mixin _HomeDashboardViewActionsMixin
    on _HomeDashboardStateBase, _HomeDashboardWallpaperMixin {
  Widget _buildWallpaperDisplay(ImageProvider<Object> provider) {
    Widget display(ImageProvider<Object> imageProvider) => Image(
      image: imageProvider,
      fit: BoxFit.cover,
      color: const Color(0x66000000),
      colorBlendMode: BlendMode.srcOver,
    );
    if (AppPlatform.isWindows) {
      return StableImageDecodeSize(
        builder: (_, width, height) => display(
          ResizeImage(
            provider,
            width: width,
            height: height,
            policy: ResizeImagePolicy.fit,
          ),
        ),
      );
    }
    return Builder(
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (size.width * pixelRatio)
            .round()
            .clamp(1, 4096)
            .toInt();
        final cacheHeight = (size.height * pixelRatio)
            .round()
            .clamp(1, 4096)
            .toInt();
        return display(
          ResizeImage(
            provider,
            width: cacheWidth,
            height: cacheHeight,
            policy: ResizeImagePolicy.fit,
          ),
        );
      },
    );
  }

  Widget _buildWallpaperWidget({
    required String wallpaperUrl,
    required ImageProvider<Object>? localWallpaperProvider,
    bool extractColor = true,
  }) {
    return RepaintBoundary(
      child: wallpaperUrl.startsWith('assets/')
          ? Builder(
              builder: (context) {
                final provider = AssetImage(wallpaperUrl);
                if (extractColor) {
                  _scheduleWallpaperColorExtraction(provider, wallpaperUrl);
                }
                return _buildWallpaperDisplay(provider);
              },
            )
          : localWallpaperProvider != null
          ? Builder(
              builder: (context) {
                final provider = localWallpaperProvider;
                if (extractColor) {
                  _scheduleWallpaperColorExtraction(provider, wallpaperUrl);
                }
                return _buildWallpaperDisplay(provider);
              },
            )
          : _WallpaperNetworkImage(
              url: _wallpaperUrl!,
              onImageProvider: extractColor
                  ? (provider) {
                      _extractColorFromProvider(provider, _wallpaperUrl!);
                    }
                  : null,
              onSuccess: () {
                _wallpaperRetryCount = 0;
              },
              onError: () {
                _handleWallpaperError();
              },
            ),
    );
  }

  Widget _buildWallpaperTopFadeCap({
    required double headerExtent,
    required String wallpaperUrl,
    required ImageProvider<Object>? localWallpaperProvider,
  }) {
    final fadeHeight = headerExtent + floatingGlassTopBarDefaultFadeTail;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: fadeHeight,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Builder(
            builder: (context) {
              final screenSize = MediaQuery.sizeOf(context);
              return ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: _resolveWallpaperTopFadeShader,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: screenSize.width,
                    maxWidth: screenSize.width,
                    minHeight: screenSize.height,
                    maxHeight: screenSize.height,
                    child: _buildWallpaperWidget(
                      wallpaperUrl: wallpaperUrl,
                      localWallpaperProvider: localWallpaperProvider,
                      extractColor: false,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openSettingsFromDrawer(
    GlobalKey sourceKey, {
    String? initialTarget,
    bool checkUpdatesOnOpen = false,
    BorderRadius sourceBorderRadius = const BorderRadius.all(
      Radius.circular(16),
    ),
    IconData placeholderIcon = Icons.settings_rounded,
  }) async {
    await PageTransitions.pushFromRect(
      context: context,
      page: SettingsPage(
        initialTarget: initialTarget,
        checkUpdatesOnOpen: checkUpdatesOnOpen,
      ),
      sourceKey: sourceKey,
      sourceBorderRadius: sourceBorderRadius,
      placeholderIcon: placeholderIcon,
    );
    if (!mounted) return;
    _loadSectionPreferences();
    _loadSemesterSettings();
    await _loadHomeTextConfig();
    if (mounted) _loadAllData(deferred: true);
  }

  Widget _buildWallpaperCopyright(bool isLight) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _wallpaperCopyright!,
              style: TextStyle(
                fontSize: 12,
                color: isLight
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _downloadWallpaper,
              child: Text(
                '喜欢该壁纸？点此下载',
                style: TextStyle(
                  fontSize: 12,
                  color: isLight
                      ? Colors.white.withValues(alpha: 0.9)
                      : Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: isLight
                      ? Colors.white.withValues(alpha: 0.9)
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadWallpaper() async {
    if (_wallpaperUrl == null) return;
    try {
      final wallpaperUrl = _wallpaperUrl!;
      late final List<int> bytes;
      late final String ext;

      if (_wallpaperUrl!.startsWith('http://') ||
          _wallpaperUrl!.startsWith('https://')) {
        final response = await _githubResourceService.get(
          Uri.parse(wallpaperUrl),
        );
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        bytes = response.bodyBytes;
        ext = _wallpaperExtension(wallpaperUrl);
      } else if (wallpaperUrl.startsWith('assets/')) {
        final data = await rootBundle.load(wallpaperUrl);
        bytes = data.buffer.asUint8List();
        ext = _wallpaperExtension(wallpaperUrl);
      } else if (wallpaperUrl.startsWith('data:')) {
        final data = UriData.parse(wallpaperUrl);
        bytes = data.contentAsBytes();
        ext = data.mimeType.split('/').last;
      } else if (_isLocalFilePath(_wallpaperUrl!)) {
        throw Exception('当前平台无法直接下载本地路径壁纸');
      } else {
        throw Exception('不支持的壁纸来源');
      }

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final savedPath = await BrowserFileService.saveBytesFile(
        Uint8List.fromList(bytes),
        'wallpaper_$ts.$ext',
        mimeType: 'image/$ext',
      );
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('已保存到 $savedPath')),
        );
      }
    } catch (e) {
      // debugPrint('下载壁纸失败: $e');
      if (mounted) {
        AppSnackBars.showSnackBar(context, SnackBar(content: Text('下载失败: $e')));
      }
    }
  }

  String _wallpaperExtension(String url) {
    final ext = url.split('?').first.split('.').last.toLowerCase();
    if (ext == 'png' || ext == 'webp' || ext == 'gif') return ext;
    return 'jpg';
  }

  Future<void> _openHomePomodoro({GlobalKey? sourceKey}) async {
    final page = PomodoroScreen(username: widget.username);
    if (sourceKey == null) {
      await Navigator.of(context).push(PageTransitions.slideHorizontal(page));
    } else {
      await PageTransitions.pushFromRect(
        context: context,
        page: page,
        sourceKey: sourceKey,
        placeholderIcon: Icons.timer_outlined,
        sourceBorderRadius: const BorderRadius.all(Radius.circular(16)),
      );
    }
    if (mounted) {
      _pomodoroRevision.value++;
      _timelineRevision.value++;
    }
  }

  Future<void> _openHomeFinanceQuickEntry() async {
    await PageTransitions.pushFromRect<FinanceTransaction>(
      context: context,
      page: const FinanceEntryScreen(),
      sourceKey: _homeAddActionKey,
      placeholderIcon: Icons.account_balance_wallet_outlined,
      sourceBorderRadius: const BorderRadius.all(Radius.circular(22)),
    );
  }

  Future<TodoCreateSaveResult> _saveManualTodo(TodoItem todo) async {
    final allTodos = await StorageService.getTodos(widget.username);
    final existingIndex = allTodos.indexWhere((item) => item.id == todo.id);
    if (existingIndex < 0) {
      allTodos.add(todo);
    } else {
      allTodos[existingIndex] = todo;
    }
    await StorageService.saveTodos(widget.username, allTodos);

    return _finishManualTodoSave(todo, allTodos);
  }

  Future<FixedScheduleTodoSaveResult> _saveTodoLinkedToFixedSchedule(
    TodoItem todo,
    FixedScheduleItem baseline,
  ) async {
    final updatedSchedule = await StorageService.saveTodoLinkedToFixedSchedule(
      widget.username,
      todo,
      baseline,
    );
    var snapshotReady = true;
    List<TodoItem> allTodos;
    try {
      allTodos = await StorageService.getTodos(widget.username);
    } catch (_) {
      snapshotReady = false;
      allTodos = _todos.map((item) => item.detachedCopy()).toList();
      final index = allTodos.indexWhere((item) => item.id == todo.id);
      if (index < 0) {
        allTodos.add(todo);
      } else {
        allTodos[index] = todo;
      }
    }
    final saveResult = await _finishManualTodoSave(
      todo,
      allTodos,
      refreshDomains: const {
        DataRefreshDomain.todos,
        DataRefreshDomain.fixedSchedules,
      },
      updateSharedSnapshots: snapshotReady,
      extraWarnings: snapshotReady ? const [] : const ['待办列表刷新失败'],
    );
    return FixedScheduleTodoSaveResult(
      schedule: updatedSchedule,
      warnings: saveResult.warnings,
    );
  }

  Future<TodoCreateSaveResult> _finishManualTodoSave(
    TodoItem todo,
    List<TodoItem> allTodos, {
    Set<DataRefreshDomain> refreshDomains = const {DataRefreshDomain.todos},
    bool updateSharedSnapshots = true,
    List<String> extraWarnings = const [],
  }) async {
    final warnings = <String>[...extraWarnings];
    Future<void> tryUpdate(
      String warning,
      FutureOr<void> Function() update,
    ) async {
      try {
        await update();
      } catch (_) {
        warnings.add(warning);
      }
    }

    if (todo.teamUuid != null) {
      await tryUpdate('团队状态待更新', () {
        PomodoroSyncService.instance.sendTeamUpdateSignal(todo.teamUuid!);
      });
    }
    if (updateSharedSnapshots) {
      await tryUpdate('共享状态待更新', () async {
        if (!await _saveTodosToSharedFile(allTodos)) {
          throw StateError('shared todo snapshot was not updated');
        }
      });
    } else {
      warnings.add('共享状态与桌面小组件待更新');
    }
    await tryUpdate('提醒待更新', () {
      FloatWindowService.triggerReminderCheck();
      FloatWindowService.invalidateSlotCache();
      _syncTodoNotification();
      _rescheduleAlarms();
    });
    if (updateSharedSnapshots) {
      await tryUpdate('桌面小组件待更新', () async {
        await WidgetService.updateTodoWidget(allTodos);
      });
    }
    await tryUpdate('首页列表待刷新', () async {
      if (mounted) {
        await _loadAllData(deferred: true, domains: refreshDomains);
        if (refreshDomains.contains(DataRefreshDomain.fixedSchedules)) {
          _scheduleRevision.value++;
          _timelineRevision.value++;
        }
      }
    });
    return TodoCreateSaveResult(warnings: warnings);
  }

  Future<void> _openHomeTodo({GlobalKey? sourceKey}) async {
    final page = AddTodoScreen(
      username: widget.username,
      todoGroups: _todoGroups,
      initialTeamUuid: _currentSelectedTeamUuid,
      initialTeamName: _currentSelectedTeamName,
      onFixedScheduleAdded: (item) async {
        await StorageService.saveFixedSchedules(widget.username, [item]);
        if (mounted) {
          _scheduleRevision.value++;
          _timelineRevision.value++;
          await _loadAllData(
            deferred: true,
            domains: const {DataRefreshDomain.fixedSchedules},
          );
        }
      },
      onTodoAdded: (todo) async {
        await _saveManualTodo(todo);
      },
      onManualTodoSaved: _saveManualTodo,
      onTodosBatchAdded: (todos) async {
        final allTodos = await StorageService.getTodos(widget.username);
        final indexById = <String, int>{};
        for (var index = 0; index < allTodos.length; index++) {
          indexById.putIfAbsent(allTodos[index].id, () => index);
        }
        for (final todo in todos) {
          final index = indexById[todo.id];
          if (index == null) {
            indexById[todo.id] = allTodos.length;
            allTodos.add(todo);
          } else {
            allTodos[index] = todo;
          }
        }
        await StorageService.saveTodos(widget.username, allTodos);
        final warnings = <String>[];
        final updatedTeamUuid = todos
            .firstWhere((t) => t.teamUuid != null, orElse: () => todos.first)
            .teamUuid;
        if (updatedTeamUuid != null) {
          try {
            PomodoroSyncService.instance.sendTeamUpdateSignal(updatedTeamUuid);
          } catch (_) {
            warnings.add('团队状态待更新');
          }
        }
        if (!await _saveTodosToSharedFile(allTodos)) {
          warnings.add('共享状态待更新');
        }
        try {
          FloatWindowService.triggerReminderCheck();
          FloatWindowService.invalidateSlotCache();
          _syncTodoNotification();
          _rescheduleAlarms();
        } catch (_) {
          warnings.add('提醒状态待更新');
        }
        try {
          await WidgetService.updateTodoWidget(allTodos);
        } catch (_) {
          warnings.add('桌面小组件待更新');
        }
        try {
          if (mounted) {
            await _loadAllData(
              deferred: true,
              domains: const {DataRefreshDomain.todos},
            );
          }
        } catch (_) {
          warnings.add('首页列表待刷新');
        }
        if (mounted && warnings.isNotEmpty) {
          AppSnackBars.showSnackBar(
            context,
            SnackBar(content: Text('待办已保存；${warnings.join('；')}')),
          );
        }
      },
      onLLMResultsParsed: (results, imagePath, originalText, tUuid, tName) {
        Navigator.pop(context);
        _navigateToTodoConfirm(results, imagePath, originalText, tUuid, tName);
      },
    );
    if (sourceKey == null) {
      await Navigator.of(context).push(PageTransitions.slideHorizontal(page));
    } else {
      await PageTransitions.pushFromRect(
        context: context,
        page: page,
        sourceKey: sourceKey,
        sourceBorderRadius: const BorderRadius.all(Radius.circular(16)),
      );
    }
  }

  Future<void> _openHomeAddCountdown() {
    return showCountdownEditorDialog(
      context: context,
      username: widget.username,
      countdowns: _countdowns,
      onDataChanged: () {
        _loadAllData(domains: const {DataRefreshDomain.countdowns});
        _timelineRevision.value++;
      },
    );
  }

  Widget _buildHomeAddOption(
    BuildContext context, {
    required Key key,
    required _HomeAddAction action,
    required IconData icon,
    required String title,
    required String subtitle,
    void Function(ModalRoute<_HomeAddAction>?)? onBeforeSelect,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: key,
        onTap: () {
          onBeforeSelect?.call(ModalRoute.of<_HomeAddAction>(context));
          Navigator.of(context).pop(action);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    icon,
                    color: colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openHomeAddMenu() async {
    ModalRoute<_HomeAddAction>? menuRoute;
    final action = await showAppModalBottomSheet<_HomeAddAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                '新增',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 132,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildHomeAddOption(
                      context,
                      key: const ValueKey<String>('home-add-todo'),
                      action: _HomeAddAction.todo,
                      icon: Icons.add_task_rounded,
                      title: '待办',
                      subtitle: '记录任务',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildHomeAddOption(
                      context,
                      key: const ValueKey<String>('home-add-countdown'),
                      action: _HomeAddAction.countdown,
                      icon: Icons.timer_rounded,
                      title: '倒计时',
                      subtitle: '设定目标日',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildHomeAddOption(
                      context,
                      key: const ValueKey<String>('home-add-finance'),
                      action: _HomeAddAction.finance,
                      icon: Icons.account_balance_wallet_outlined,
                      title: '记账',
                      subtitle: '收入或支出',
                      onBeforeSelect: (route) => menuRoute = route,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == _HomeAddAction.finance) {
      // The sheet result arrives before its exit animation finishes.
      await menuRoute?.completed;
      if (!mounted) return;
    }

    switch (action) {
      case _HomeAddAction.todo:
        await _openHomeTodo(sourceKey: _homeAddActionKey);
      case _HomeAddAction.countdown:
        await _openHomeAddCountdown();
      case _HomeAddAction.finance:
        await _openHomeFinanceQuickEntry();
    }
  }

  Widget _buildCustomBottomBar(bool isDarkMode, bool isLight, bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color primaryColor = homeBottomBarPrimaryColor(
      colorScheme: colorScheme,
      hasWallpaper: isLight,
      wallpaperDominantColor: _wallpaperDominantColor,
    );
    final Color inactiveColor = isLight
        ? colorScheme.scrim.withValues(alpha: 0.86)
        : colorScheme.onSurfaceVariant;
    final double bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    // The reference rests as a neutral frosted capsule. Keep only a trace of
    // the action color here; the icon and label carry the strong selection.
    final selectedBackgroundColor = homeBottomBarSelectedBackgroundColor(
      colorScheme: colorScheme,
      primaryColor: primaryColor,
      isDark: isDarkMode,
    );

    final double height =
        60.0 + (bottomPadding > 0 ? bottomPadding * 0.5 : 6.0);
    final margin = floatingBottomNavigationMarginFor(
      context,
      itemCount: isWide ? 3 : 5,
    );

    final glassTint = Color.alphaBlend(
      primaryColor.withValues(alpha: 0.08),
      colorScheme.surface,
    ).withValues(alpha: isDarkMode ? 0.24 : 0.32);

    return _HomeDashboardBottomBar(
      selectedIndex: _selectedTabIndex,
      primaryColor: primaryColor,
      inactiveColor: inactiveColor,
      selectedBackgroundColor: selectedBackgroundColor,
      weeklyButtonKey: _courseCenterKey,
      addButtonKey: _homeAddActionKey,
      pomodoroButtonKey: _homePomodoroActionKey,
      isWide: isWide,
      height: height,
      margin: margin,
      isDarkMode: isDarkMode,
      glassTint: glassTint,
      onTabSelected: (index) {
        setState(() {
          _selectedTabIndex = index;
          if (index == _homeFocusTabIndex) {
            _focusTabVisited = true;
          }
        });
        if (index == _homeFocusTabIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkFocusTabCoachMarks();
          });
        }
      },
      onWeeklyPressed: () {
        PageTransitions.pushFromRect(
          context: context,
          page: WeeklyCourseScreen(
            username: widget.username,
            onCreateRelatedTodo: _saveTodoLinkedToFixedSchedule,
          ),
          sourceKey: _courseCenterKey,
        );
      },
      onAddPressed: () {
        _openHomeAddMenu();
      },
      onAddLongPress: _openQuickVoiceChat,
      onAddLongPressStart: _startQuickVoiceGesture,
      onAddLongPressMoveUpdate: _moveQuickVoiceGesture,
      onAddLongPressEnd: _endQuickVoiceGesture,
      onAddLongPressCancel: _cancelQuickVoiceGesture,
      onPomodoroPressed: () {
        _openHomePomodoro(sourceKey: _homePomodoroActionKey);
      },
    );
  }

  bool _isRevisionedEntityEqual(Object? a, Object? b) {
    if (a is TodoItem && b is TodoItem) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.isDone == b.isDone &&
          a.isDeleted == b.isDeleted &&
          a.hasConflict == b.hasConflict;
    }
    if (a is TodoGroup && b is TodoGroup) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.isExpanded == b.isExpanded &&
          a.isDeleted == b.isDeleted &&
          a.hasConflict == b.hasConflict;
    }
    if (a is CountdownItem && b is CountdownItem) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.isCompleted == b.isCompleted &&
          a.isDeleted == b.isDeleted &&
          a.hasConflict == b.hasConflict;
    }
    if (a is TodoPlanBlock && b is TodoPlanBlock) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.status == b.status &&
          a.isDeleted == b.isDeleted;
    }
    if (a is FixedScheduleItem && b is FixedScheduleItem) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.status == b.status &&
          a.isDeleted == b.isDeleted;
    }
    if (a is CourseItem && b is CourseItem) {
      return a.uuid == b.uuid &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.isDeleted == b.isDeleted;
    }
    return false;
  }

  bool _isDeepValueEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.runtimeType != b.runtimeType) return false;
    if (_isRevisionedEntityEqual(a, b)) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var index = 0; index < a.length; index++) {
        if (!_isDeepValueEqual(a[index], b[index])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_isDeepValueEqual(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  // 内容级比较用于阻止相同数据库快照触发无意义的模块重建。
  bool _isListEqual(List a, List b) {
    return _isDeepValueEqual(a, b);
  }

  bool _isMapEqual(Map a, Map b) {
    return _isDeepValueEqual(a, b);
  }

  Widget _buildOnboardingChecklistSection(bool isLight) {
    final courses = _safeListResult<CourseItem>(
      _dashboardCourseData['courses'],
    );
    final hasTodosOrCountdowns =
        _todos.any((t) => !t.isDeleted) || _countdowns.any((c) => !c.isDeleted);
    final hasCoursesOrSchedules = courses.any((c) => !c.isDeleted);
    final hasPlanBlocks = _planBlocks.any((b) => !b.isDeleted);

    return OnboardingChecklistCard(
      isLight: isLight,
      hasTodosOrCountdowns: hasTodosOrCountdowns,
      hasCoursesOrSchedules: hasCoursesOrSchedules,
      hasPlanBlocks: hasPlanBlocks,
      onLaunchTask: _handleOnboardingTaskLaunch,
      onSpotlightTask: _handleOnboardingTaskSpotlight,
      onOpenFeatureExplorer: () {
        Navigator.of(context, rootNavigator: true).push(
          PageTransitions.slideHorizontal(
            FeatureExplorerScreen(username: widget.username),
          ),
        );
      },
    );
  }

  Future<void> _handleOnboardingTaskLaunch(String taskId) async {
    await OnboardingChecklistService.markTaskCompleted(taskId);
    if (!mounted) return;
    switch (taskId) {
      case OnboardingChecklistService.taskCreateTodoOrCountdown:
        await _openHomeAddMenu();
      case OnboardingChecklistService.taskCourseOrSchedule:
        await PageTransitions.pushFromRect(
          context: context,
          page: WeeklyCourseScreen(
            username: widget.username,
            onCreateRelatedTodo: _saveTodoLinkedToFixedSchedule,
          ),
          sourceKey: _courseCenterKey,
        );
      case OnboardingChecklistService.taskPlanBlock:
        await Navigator.of(context).push(
          PageTransitions.material(
            builder: (_) => TodoPlanScreen(username: widget.username),
          ),
        );
        if (mounted) {
          _scheduleRevision.value++;
          _loadAllData(
            domains: const {
              DataRefreshDomain.todos,
              DataRefreshDomain.planBlocks,
              DataRefreshDomain.fixedSchedules,
            },
          );
        }
      case OnboardingChecklistService.taskPomodoroFocus:
        await _openHomePomodoro(sourceKey: _homePomodoroActionKey);
      case OnboardingChecklistService.taskAiOrQuickVoice:
        await _openAiAssistantFromAppBar();
      case OnboardingChecklistService.taskExploreFeatureHub:
        await Navigator.of(context, rootNavigator: true).push(
          PageTransitions.slideHorizontal(
            FeatureExplorerScreen(username: widget.username),
          ),
        );
    }
  }

  Future<void> _handleOnboardingTaskSpotlight(String taskId) async {
    if (_showCoachMarks || !mounted) return;
    final CoachMarkStep? step = switch (taskId) {
      OnboardingChecklistService.taskCreateTodoOrCountdown => CoachMarkStep(
        targetKey: _homeAddActionKey,
        title: '新建待办 / 倒计时 / 记账',
        description: '点这里可快速创建待办事项、重要日倒计时或记一笔账；长按还能直接语音速记！',
        buttonLabel: '立即打开',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskCourseOrSchedule => CoachMarkStep(
        targetKey: _courseCenterKey,
        title: '周视图与课程表/固定日程',
        description: '在这里查看整周课程表、创建每周重复的固定日程，并支持将待办关联到固定日程。',
        buttonLabel: '进入周视图',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskPlanBlock => CoachMarkStep(
        targetKey: _todayPlanChartKey,
        title: '今日日程与规划中心',
        description: '点击这里可将待办安排到具体时间块，把“要做什么”变成“什么时候做”。',
        buttonLabel: '去规划',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskPomodoroFocus => CoachMarkStep(
        targetKey: _homePomodoroActionKey,
        title: '番茄钟专注工作台',
        description: '点击这里开启番茄钟倒计时或正计时专注，支持绑定待办并跨设备实时同步专注状态。',
        buttonLabel: '去专注',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskAiOrQuickVoice => CoachMarkStep(
        targetKey: _aiButtonKey,
        title: 'AI 智能助手',
        description: '点击顶部机器人图标进入 AI 对话，或长按底部「+」按钮语音速记，一句话搞定排期与记账。',
        buttonLabel: '打开 AI 助手',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskExploreFeatureHub => CoachMarkStep(
        targetKey: _menuKey,
        title: '侧边栏与功能百宝箱',
        description: '点击左上角打开侧边栏，可随时进入「功能百宝箱」、记账、习惯中心、挑战中心、私密日记与设置中心。',
        buttonLabel: '打开百宝箱',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      _ => null,
    };
    if (step == null || step.targetKey.currentContext == null) {
      await _handleOnboardingTaskLaunch(taskId);
      return;
    }
    _showCoachMarks = true;
    try {
      await CoachMarkOverlay.show(
        context: context,
        steps: [step],
        onFinish: () => _showCoachMarks = false,
        onSkip: () => _showCoachMarks = false,
      );
    } finally {
      _showCoachMarks = false;
    }
  }

  Widget _buildDashboardSkeleton(bool isLight, {double topPadding = 16}) {
    final baseColor = isLight
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.grey[800]!;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
      child: Column(
        children: [
          _buildSkeletonCard(baseColor, height: 120),
          const SizedBox(height: 16),
          _buildSkeletonCard(baseColor, height: 180),
          const SizedBox(height: 16),
          _buildSkeletonCard(baseColor, height: 240),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard(Color color, {required double height}) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
