part of 'todo_chat_screen.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatLayout on _TodoChatScreenStateBase {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 900) {
                return _buildWideLayout(
                  isDark,
                  colorScheme,
                );
              }
              return _buildMobileLayout(isDark, colorScheme);
            },
          ),
          _buildFloatingResponsiveAppBar(isDark, colorScheme),
        ],
      ),
    );
  }

  Widget _buildFloatingResponsiveAppBar(
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: floatingGlassTopBarHeight(context),
        child: Padding(
          padding: EdgeInsets.only(top: topInset),
          child: _buildResponsiveAppBar(isDark, colorScheme),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildResponsiveAppBar(
      bool isDark, ColorScheme colorScheme) {
    return FloatingGlassAppBar(
      primary: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      forceMaterialTransparency: true,
      systemOverlayStyle: floatingGlassTopBarSystemOverlayStyle(context),
      flexibleSpace: const FloatingGlassTopBarBackground(),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
        tooltip: '返回',
      ),
      title: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _isWide ? 320 : 190),
        child: Column(
          children: [
            Text(
              _getCurrentSessionTitle(),
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                _isLoading ? '正在思考...' : 'AI 助手在线',
                key: ValueKey(_isLoading),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.normal,
                  color: _isLoading
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          key: _historyKey,
          icon: Icon(
            _isWide
                ? (_sidebarVisible
                    ? Icons.keyboard_double_arrow_left_rounded
                    : Icons.keyboard_double_arrow_right_rounded)
                : Icons.history_rounded,
            size: 22,
          ),
          onPressed: _isWide
              ? () => setState(() => _sidebarVisible = !_sidebarVisible)
              : _showHistorySidebar,
          tooltip: _isWide ? (_sidebarVisible ? '隐藏侧边栏' : '显示侧边栏') : '历史对话',
        ),
        IconButton(
          key: _newSessionKey,
          icon: const Icon(Icons.add_comment_rounded, size: 22),
          onPressed: _newSession,
          tooltip: '新建对话',
        ),
        IconButton(
          key: _settingsKey,
          icon: const Icon(Icons.tune_rounded, size: 22),
          onPressed: _showPromptSettings,
          tooltip: '提示词设置',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildWideLayout(
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final useActionRail = _usesActionRail;
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          width: _sidebarVisible ? 304 : 0,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              right: BorderSide(
                color: colorScheme.outlineVariant.withValues(
                  alpha: _sidebarVisible ? 0.7 : 0,
                ),
              ),
            ),
          ),
          child: ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: _sidebarVisible ? 1 : 0,
              child: SizedBox(
                width: 304,
                child: _buildHistorySidebarContent(context, isWideMode: true),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: useActionRail ? 760 : 920,
                    ),
                    child: FloatingGlassTopBarContentFade(
                      topBarHeight: floatingGlassTopBarHeight(context),
                      child: _buildMessageList(isDark, colorScheme),
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      if (!useActionRail)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              SizeTransition(
                            sizeFactor: animation,
                            alignment: AlignmentDirectional.bottomStart,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          ),
                          child: _suggestions.isNotEmpty && !_isLoading
                              ? _buildSuggestionsArea(colorScheme)
                              : const SizedBox.shrink(),
                        ),
                      _buildInputArea(colorScheme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (useActionRail)
          SizedBox(
            width: 344,
            child: _buildActionRail(isDark, colorScheme),
          )
        else if (_shouldDetachActions)
          SizedBox(
            width: 48,
            child: _buildCollapsedActionRailHandle(colorScheme),
          ),
      ],
    );
  }

  List<ChatMessage> get _pendingActionMessages {
    return _messages
        .where(
          (msg) =>
              msg.todoActions != null &&
              msg.todoActions!.any(
                (action) => !action.isAdded && !action.isIgnored,
              ),
        )
        .toList()
        .reversed
        .toList();
  }

  Widget _buildActionRail(bool isDark, ColorScheme colorScheme) {
    final actionMessages = _pendingActionMessages;
    final actionCount = _pendingActionCount;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.68),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_motion_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '建议操作',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: actionCount == 0
                      ? const SizedBox.shrink()
                      : Text(
                          '$actionCount',
                          key: ValueKey(actionCount),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  tooltip: '收起建议操作',
                  onPressed: () => setState(() => _actionRailCollapsed = true),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.62),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: actionMessages.isEmpty && _suggestions.isEmpty
                  ? _buildActionRailEmptyState(colorScheme)
                  : ListView(
                      key: ValueKey(
                        '${actionMessages.length}-${_suggestions.length}',
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                      children: [
                        if (actionMessages.isNotEmpty)
                          ...actionMessages.map(
                            (msg) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildMessageTodoActions(msg, isDark),
                            ),
                          ),
                        if (_suggestions.isNotEmpty && !_isLoading) ...[
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              4,
                              actionMessages.isNotEmpty ? 8 : 0,
                              4,
                              10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline_rounded,
                                  size: 16,
                                  color: colorScheme.secondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '下一步问题',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ..._suggestions.map(
                            (text) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildQuickQuestion(
                                text,
                                compact: true,
                                expand: true,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedActionRailHandle(ColorScheme colorScheme) {
    final count = _pendingActionCount;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.68),
          ),
        ),
      ),
      child: Center(
        child: Tooltip(
          message: '展开建议操作',
          child: Material(
            color: colorScheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _actionRailCollapsed = false),
              child: SizedBox(
                width: 36,
                height: 96,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.keyboard_double_arrow_left_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionRailEmptyState(ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('empty-action-rail'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 34,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无待执行操作',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '模型生成可执行的待办、日程或其他操作后会出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(bool isDark, ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          child: FloatingGlassTopBarContentFade(
            topBarHeight: floatingGlassTopBarHeight(context),
            child: _buildMessageList(isDark, colorScheme),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: AlignmentDirectional.bottomStart,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          ),
          child: _suggestions.isNotEmpty && !_isLoading
              ? _buildSuggestionsArea(colorScheme)
              : const SizedBox.shrink(),
        ),
        _buildInputArea(colorScheme),
      ],
    );
  }

  Widget _buildMessageList(bool isDark, ColorScheme colorScheme) {
    if (_messages.isEmpty) {
      return _buildEmptyState(colorScheme);
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: EdgeInsets.fromLTRB(
        16,
        floatingGlassTopBarHeight(context) + 18,
        16,
        20,
      ),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoading && index == _messages.length) {
          return _StaggeredFadeSlide(
            delay: Duration.zero,
            child: _buildStreamingBubble(isDark),
          );
        }
        final msg = _messages[index];
        return TweenAnimationBuilder<double>(
          key: ValueKey(msg.timestamp.millisecondsSinceEpoch + index),
          duration: const Duration(milliseconds: 500),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.easeOutQuart,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: _buildMessageBubble(msg, isDark),
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StaggeredFadeSlide(
                delay: const Duration(milliseconds: 40),
                child: _PulseAvatar(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color:
                          colorScheme.primaryContainer.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.smart_toy_rounded,
                      size: 36,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _StaggeredFadeSlide(
                delay: const Duration(milliseconds: 110),
                child: Text(
                  'AI效率助手',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _StaggeredFadeSlide(
                delay: const Duration(milliseconds: 170),
                child: Text(
                  '可以直接问日程、课程、待办、规划块和专注记录，也可以让它生成可执行操作。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _StaggeredFadeSlide(
                delay: const Duration(milliseconds: 200),
                child: OutlinedButton.icon(
                  onPressed: _openTutorialPage,
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('查看使用教程'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _StaggeredFadeSlide(
                child: SizedBox(
                  height: _isWide ? 180 : 140,
                  width: double.infinity,
                  child: _DanmakuSuggestions(
                    suggestions: _getSmartSuggestions(),
                    onTap: (text) {
                      _inputCtrl.text = text;
                      _sendMessage();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsArea(ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
      ),
      child: SizedBox(
        height: 50,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) => _buildQuickQuestion(
            _suggestions[index],
            compact: true,
          ),
        ),
      ),
    );
  }

  String _getCurrentSessionTitle() {
    final session = _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => ChatSession(title: 'AI效率助手'),
    );
    return session.title;
  }

  void _showHistorySidebar() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Stack(
          children: [
            ModalBarrier(
              color: Colors.black.withValues(
                alpha: 0.3 * anim1.value,
              ),
              dismissible: true,
            ),
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.75,
                  height: MediaQuery.of(context).size.height,
                  margin: const EdgeInsets.only(top: kToolbarHeight + 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(4, 0),
                      ),
                    ],
                  ),
                  child: _buildHistorySidebarContent(ctx, isWideMode: false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistorySidebarContent(BuildContext context,
      {required bool isWideMode}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, isWideMode ? 18 : 16, 12, 10),
          child: Row(
            children: [
              Text(
                '对话',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () => _deleteAllSessions(context),
                tooltip: '清空所有历史对话',
              ),
              if (!isWideMode)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        Expanded(
          child: _sessions.isEmpty
              ? Center(
                  child: Text(
                    '暂无历史对话',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: _sessions.length,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final isActive = session.id == _activeSessionId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: isActive
                            ? colorScheme.primaryContainer
                                .withValues(alpha: 0.55)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          dense: isWideMode,
                          minLeadingWidth: 24,
                          horizontalTitleGap: 10,
                          contentPadding:
                              const EdgeInsets.only(left: 12, right: 4),
                          leading: Icon(
                            isActive
                                ? Icons.chat_bubble_rounded
                                : Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: isActive
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                              color: isActive
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            DateFormat('MM/dd HH:mm').format(
                              session.updatedAt,
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: colorScheme.onSurfaceVariant,
                            onPressed: () {
                              if (!isWideMode) Navigator.pop(context);
                              _deleteSession(session.id);
                            },
                            tooltip: '删除对话',
                          ),
                          selected: isActive,
                          selectedTileColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: () {
                            if (!isWideMode) Navigator.pop(context);
                            _switchSession(session.id);
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _deleteAllSessions(BuildContext sidebarCtx) async {
    final confirmed = await showDialog<bool>(
      context: sidebarCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底清空对话历史'),
        content: const Text('确定要删除所有的历史对话吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ChatStorageService.clearAllSessions();
      if (!mounted || !sidebarCtx.mounted) return;
      setState(() {
        _sessions = [];
        _messages = [];
        _activeSessionId = '';
        _suggestions = _getSmartSuggestions();
      });
      // 关闭侧边栏
      Navigator.pop(sidebarCtx);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空所有历史对话')),
      );
    }
  }

  static const Map<String, String> providerLabels = {
    'zhipu': '智谱AI',
    'mimo': '小米MiMo',
    AiChatService.mimoTokenPlanProvider: 'MiMo Token Plan',
    'deepseek': 'DeepSeek',
    'nvidia_nim': 'NVIDIA NIM',
    'custom': '自定义',
  };

  Widget _buildModelSelector() {
    final inheritedModel =
        _globalModelName.isNotEmpty ? _globalModelName : '未配置';
    final inheritedProvider = _globalProvider.isNotEmpty
        ? providerLabels[_globalProvider] ?? _globalProvider
        : '';
    final labelSuffix =
        inheritedProvider.isNotEmpty ? ' ($inheritedProvider)' : '';
    final labelPrefix = _chatModel.isNotEmpty ? '' : '继承: ';
    String label = _chatModel.isNotEmpty
        ? _chatModel
        : '$labelPrefix$inheritedModel$labelSuffix';

    return PopupMenuButton<String>(
      tooltip: '模型配置',
      icon: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.model_training_outlined,
              size: 18,
              color: _chatModel.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _chatModel.isNotEmpty
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: '__global__',
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: _chatModel.isEmpty
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '继承全局配置: $inheritedModel$labelSuffix',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (_chatModel.isNotEmpty)
          PopupMenuItem(
            value: '__current__',
            enabled: false,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前: $_chatModel',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__settings__',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 16),
              SizedBox(width: 8),
              Text('打开LLM配置...'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: '__custom__',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 8),
              Text('自定义模型...'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == '__custom__') {
          _showModelConfig();
        } else if (value == '__settings__') {
          _openLlmConfigPage();
        } else if (value == '__global__') {
          _useGlobalModel();
        }
      },
    );
  }

  Future<void> _useGlobalModel() async {
    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.llmConfiguration,
    );
    if (!authorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              MinorModeService.instance.authorizationFailureMessage(
                MinorModeAction.llmConfiguration,
              ),
            ),
          ),
        );
      }
      return;
    }
    await ChatStorageService.clearChatConfig();
    final globalConfig = await LLMService.getConfig();
    if (mounted) {
      setState(() {
        _chatModel = '';
        _chatApiKey = '';
        _chatApiUrl = '';
        _chatProvider = '';
        _globalModelName = globalConfig?.model ?? '';
        _globalProvider = globalConfig?.provider ?? '';
      });
    }
  }

  Future<void> _openLlmConfigPage() async {
    await Navigator.push(
      context,
      PageTransitions.material(builder: (_) => const LLMConfigPage()),
    );
    if (!mounted) return;
    await _loadChatConfig();
  }

  Future<void> _showModelConfig() async {
    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.llmConfiguration,
    );
    if (!authorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              MinorModeService.instance.authorizationFailureMessage(
                MinorModeAction.llmConfiguration,
              ),
            ),
          ),
        );
      }
      return;
    }
    final globalConfig = await LLMService.getConfig();
    if (!mounted) return;
    final modelCtrl = TextEditingController(
      text: _chatModel.isNotEmpty ? _chatModel : globalConfig?.model ?? '',
    );
    final apiKeyCtrl = TextEditingController(
      text: _chatApiKey.isNotEmpty ? _chatApiKey : globalConfig?.apiKey ?? '',
    );
    final apiUrlCtrl = TextEditingController(
      text: _chatApiUrl.isEmpty
          ? globalConfig?.apiUrl ??
              'https://open.bigmodel.cn/api/paas/v4/chat/completions'
          : _chatApiUrl,
    );
    String customProvider =
        _chatProvider.isNotEmpty ? _chatProvider : globalConfig?.provider ?? '';
    bool useCustom = _chatModel.isNotEmpty;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('聊天模型配置'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用独立模型配置'),
                    subtitle: Text(
                      globalConfig?.isConfigured == true
                          ? '关闭后继承全局模型: ${globalConfig!.model}'
                          : '关闭后继承全局配置；当前全局未配置',
                    ),
                    value: useCustom,
                    onChanged: (val) {
                      setDialogState(() => useCustom = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtrl,
                    enabled: useCustom,
                    decoration: InputDecoration(
                      labelText: '模型名称',
                      hintText: '例如: glm-4.7-flash',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyCtrl,
                    enabled: useCustom,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: '输入你的API密钥',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiUrlCtrl,
                    enabled: useCustom,
                    decoration: InputDecoration(
                      labelText: 'API地址 (可选)',
                      hintText:
                          'https://open.bigmodel.cn/api/paas/v4/chat/completions',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: providerLabels.containsKey(customProvider)
                        ? customProvider
                        : null,
                    decoration: InputDecoration(
                      labelText: '提供商 (可选)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: providerLabels.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: useCustom
                        ? (val) {
                            final nextProvider = val ?? '';
                            setDialogState(() {
                              customProvider = nextProvider;
                              if (nextProvider ==
                                      AiChatService.mimoTokenPlanProvider &&
                                  (apiUrlCtrl.text.trim().isEmpty ||
                                      apiUrlCtrl.text.trim() ==
                                          AiChatService.defaultApiUrl)) {
                                apiUrlCtrl.text =
                                    AiChatService.mimoTokenPlanOpenAiBaseUrl;
                              }
                            });
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            if (useCustom)
              TextButton(
                onPressed: () async {
                  await ChatStorageService.clearChatConfig();
                  final globalConfig = await LLMService.getConfig();
                  if (mounted) {
                    setState(() {
                      _chatModel = '';
                      _chatApiKey = '';
                      _chatApiUrl = '';
                      _chatProvider = '';
                      _globalModelName = globalConfig?.model ?? '';
                      _globalProvider = globalConfig?.provider ?? '';
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('清除'),
              ),
            FilledButton(
              onPressed: useCustom
                  ? () async {
                      if (modelCtrl.text.trim().isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入模型名称')),
                        );
                        return;
                      }
                      if (apiKeyCtrl.text.trim().isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入API密钥')),
                        );
                        return;
                      }
                      await ChatStorageService.saveChatConfig(
                        model: modelCtrl.text.trim(),
                        apiKey: apiKeyCtrl.text.trim(),
                        apiUrl: apiUrlCtrl.text.trim().isEmpty
                            ? null
                            : apiUrlCtrl.text.trim(),
                        provider: useCustom && customProvider.isNotEmpty
                            ? customProvider
                            : null,
                      );
                      if (mounted) {
                        setState(() {
                          _chatModel = modelCtrl.text.trim();
                          _chatApiKey = apiKeyCtrl.text.trim();
                          _chatApiUrl = apiUrlCtrl.text.trim();
                          _chatProvider = useCustom && customProvider.isNotEmpty
                              ? customProvider
                              : '';
                          _globalModelName = globalConfig?.model ?? '';
                          _globalProvider = globalConfig?.provider ?? '';
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  : null,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getSmartSuggestions() {
    final List<String> suggestions = [];

    // 1. 基础引导 (恒定)
    suggestions.addAll([
      '帮我规划今天的待办',
      '怎么使用深度规划？',
      '分析一下我最近的效率',
      '有哪些紧急任务需要处理？',
    ]);

    // 2. 基于课程数据
    if (widget.courses.isNotEmpty) {
      suggestions.add('明天的课程表是什么？');
      suggestions.add('这周我还有多少节课？');
      suggestions.add('按课程空档规划待办');
    }

    // 3. 基于待办状态
    if (widget.todos.isNotEmpty) {
      final highPriority =
          widget.todos.where((t) => (t['priority'] ?? 0) >= 2).length;
      if (highPriority > 0) suggestions.add('列出所有高优先级任务');

      final overdue = widget.todos.where((t) {
        final dueDate = t['dueDate'] as String?;
        if (dueDate == null || dueDate.isEmpty) return false;
        final date = DateTime.tryParse(dueDate);
        return date != null && date.isBefore(DateTime.now());
      }).length;
      if (overdue > 0) suggestions.add('有哪些任务已经逾期了？');

      suggestions.add('帮我给这些待办分个类');
      suggestions.add('预测一下我完成所有任务需要多久');
    }

    // 4. 基于专注记录
    if (widget.pomodoroRecords.isNotEmpty) {
      suggestions.add('我这周专注时长达标了吗？');
      suggestions.add('分析我的专注分布情况');
    }

    // 5. 基于倒计时/目标
    if (widget.countdowns.isNotEmpty) {
      suggestions.add('最近的考试/目标还有多久？');
    }

    // 6. 基于规划冲突
    if (widget.conflicts.isNotEmpty) {
      suggestions.add('帮我解决目前的规划冲突');
    }

    // 7. 通用高级技巧
    suggestions.addAll([
      '帮我整理番茄标签',
      '如何提高我的专注力？',
      '整理一下我的时间日志',
      '帮我制定一个复习计划',
      '有哪些建议能让我更自律？',
    ]);

    return suggestions.toSet().toList();
  }
}
