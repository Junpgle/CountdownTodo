part of '../feature_guide_screen.dart';

extension _FeatureGuideChangelogAndPlatformPages on _FeatureGuideScreenState {
  // ── 页面 1: 更新日志 (基于原有旧代码迁移) ───────────────────

  Widget _buildChangelogPage() {
    final current = _changelogHistory.isNotEmpty
        ? _changelogHistory.first
        : null;
    final history = _changelogHistory.length > 1
        ? _changelogHistory.sublist(1)
        : <ChangelogEntry>[];
    final scheme = Theme.of(context).colorScheme;
    final previous = _normalizeVersion(_previousShownVersion);
    final currentVersion = _normalizeVersion(_currentVersion);
    final displayVersion = current?.versionName ?? currentVersion;
    final showVersionRange =
        previous.isNotEmpty &&
        _compareVersionNames(previous, currentVersion) < 0 &&
        _changelogHistory.length > 1;

    return _buildPageContainer(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              children: [
                Icon(
                  Icons.system_update_rounded,
                  size: 28,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _loadingChangelog
                        ? '版本更新 (Loading)'
                        : 'v$displayVersion 更新日志',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (showVersionRange) ...[
            Text(
              '从 v$previous 升级到 v$currentVersion，以下是本次跨版本变动。',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.65),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_changelogNotice != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _changelogNotice!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 当前版本
          OptionalLiquidGlassCard(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            borderRadius: 16,
            highContrast: true,
            tint: scheme.primary.withValues(alpha: 0.16),
            fallbackDecoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'v${current?.versionName ?? _currentVersion}',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (current?.date.isNotEmpty == true)
                      Text(
                        current!.date,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_loadingChangelog)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (_changelogFetchFailed)
                  Text(
                    '请联网后查看详细更新内容。',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  )
                else if (current == null || current.items.isEmpty)
                  Text(
                    '本版本暂无更新日志。',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  )
                else
                  ...current.items.map(
                    (item) => _buildBulletItem(item, scheme),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 🧭 功能探索百宝箱入口
          _buildFeatureExplorerBanner(scheme),
          const SizedBox(height: 24),
          // 历史版本
          if (history.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 6),
                Text(
                  '历史版本',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...history.map((e) => _buildHistoryVersionTile(e)),
          ],
        ],
      ),
    );
  }

  ({String label, Widget Function() builder})? _resolveChangelogItemDestination(
    String item,
  ) {
    if (_isFirstLaunch) return null;
    final username = widget.loggedInUser ?? '';
    if (item.contains('固定日程') || item.contains('课表') || item.contains('周视图')) {
      return (
        label: '去周视图',
        builder: () => WeeklyCourseScreen(username: username),
      );
    }
    if (item.contains('记账') ||
        item.contains('账单') ||
        item.contains('结余') ||
        item.contains('财务')) {
      return (
        label: '去记账',
        builder: () => FinanceHomeScreen(username: username),
      );
    }
    if (item.contains('习惯')) {
      return (
        label: '去习惯',
        builder: () => HabitCenterScreen(username: username),
      );
    }
    if (item.contains('规划') || item.contains('时间块')) {
      return (label: '去规划', builder: () => TodoPlanScreen(username: username));
    }
    if (item.contains('回收站') || item.contains('历史待办')) {
      return (
        label: '去回收站',
        builder: () => HistoricalTodosScreen(username: username),
      );
    }
    if (item.contains('番茄') || item.contains('专注会话')) {
      return (label: '去专注', builder: () => PomodoroScreen(username: username));
    }
    if (item.contains('AI') || item.contains('智能识别')) {
      return (label: '看教程', builder: () => const AiAssistantTutorialScreen());
    }
    if (item.contains('挑战')) {
      return (label: '去挑战', builder: () => const ChallengeCenterScreen());
    }
    if (item.contains('时间轴') || item.contains('个人报告')) {
      return (
        label: '看报告',
        builder: () => PersonalTimelineScreen(username: username),
      );
    }
    if (item.contains('搜索')) {
      return (label: '去搜索', builder: () => const GlobalSearchOverlay());
    }
    if (item.contains('动画') ||
        item.contains('液态玻璃') ||
        item.contains('Liquid Glass')) {
      return (label: '动效设置', builder: () => const AnimationSettingsPage());
    }
    if (item.contains('主题') || item.contains('色彩') || item.contains('外观')) {
      return (
        label: '外观设置',
        builder: () =>
            const PreferenceSettingsPage(initialTarget: 'theme_color'),
      );
    }
    return null;
  }

  Widget _buildBulletItem(
    String item,
    ColorScheme scheme, {
    double textAlpha = 0.75,
    double fontSize = 13.5,
  }) {
    final destination = item.startsWith('【新增】') || item.startsWith('【优化】')
        ? _resolveChangelogItemDestination(item)
        : null;

    return ChangelogBulletItem(
      item: item,
      textAlpha: textAlpha,
      fontSize: fontSize,
      trailing: destination == null
          ? null
          : InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                Navigator.of(context, rootNavigator: true).push(
                  PageTransitions.material(
                    builder: (_) => destination.builder(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${destination.label} →',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHistoryVersionTile(ChangelogEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final isExpanded = _expandedVersions.contains(entry.versionName);
    return Column(
      children: [
        InkWell(
          onTap: () => _mutateState(() {
            if (isExpanded) {
              _expandedVersions.remove(entry.versionName);
            } else {
              _expandedVersions.add(entry.versionName);
            }
          }),
          borderRadius: BorderRadius.circular(12),
          child: OptionalLiquidGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            borderRadius: 12,
            highContrast: true,
            fallbackDecoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  'v${entry.versionName}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(width: 8),
                if (entry.date.isNotEmpty)
                  Text(
                    entry.date,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                const Spacer(),
                if (!isExpanded && entry.items.isNotEmpty)
                  Flexible(
                    child: Text(
                      entry.items.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: OptionalLiquidGlassCard(
            margin: const EdgeInsets.only(top: 2, bottom: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            borderRadiusGeometry: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            highContrast: true,
            fallbackDecoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entry.items
                  .map(
                    (item) => _buildBulletItem(
                      item,
                      scheme,
                      textAlpha: 0.65,
                      fontSize: 12.5,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildFeatureExplorerBanner(ColorScheme scheme) {
    if (_isFirstLaunch) return const SizedBox.shrink();
    return InkWell(
      key: const ValueKey<String>('changelog-open-feature-explorer-card'),
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          PageTransitions.slideHorizontal(
            FeatureExplorerScreen(username: widget.loggedInUser),
          ),
        );
      },
      child: OptionalLiquidGlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 16,
        highContrast: true,
        tint: scheme.primary.withValues(alpha: 0.18),
        fallbackDecoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.7),
              scheme.tertiaryContainer.withValues(alpha: 0.5),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.explore_rounded,
                color: scheme.onPrimary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '打开「功能探索百宝箱」',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '不知道软件有哪些功能、入口藏在哪里？一图总览全部模块与隐藏神技',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  // ── Web / macOS 特性及能力取舍 ───────────────────────────

  Widget _buildWebFeaturePage() {
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.web_asset_rounded,
            iconColor: scheme.primary,
            title: '网页版 Beta',
            subtitle:
                '无需安装即可在浏览器中使用待办、倒数日、番茄钟、课表和同步。首次加载资源较多，安装为 PWA 后再次打开会更快。',
          ),
          const SizedBox(height: 28),
          _buildCapabilityTile(
            icon: Icons.task_alt_rounded,
            title: '核心数据与同步可用',
            subtitle: '待办、倒数日、番茄钟、课表、个人时间轴和云端同步均可在网页端运行。',
            color: scheme.primary,
          ),
          const SizedBox(height: 12),
          _buildCapabilityTile(
            icon: Icons.install_desktop_rounded,
            title: '支持 PWA 安装',
            subtitle: '在支持的浏览器中可安装到桌面/启动台，并缓存 Flutter 引擎、字体和离线资源。',
            color: scheme.secondary,
          ),
          const SizedBox(height: 12),
          _buildCapabilityTile(
            icon: Icons.folder_open_rounded,
            title: '文件流程改为浏览器模式',
            subtitle: '导入使用浏览器文件选择，导出和壁纸下载会触发浏览器下载。',
            color: scheme.tertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildWebCapabilityPage() {
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.tune_rounded,
            iconColor: scheme.error,
            title: '网页版功能取舍',
            subtitle: '浏览器无法提供完整系统权限，因此部分原生能力会隐藏、降级或改用网页替代方案。',
          ),
          const SizedBox(height: 28),
          _buildCapabilityTile(
            icon: Icons.notifications_off_outlined,
            title: '系统级通知与后台保活受限',
            subtitle: '网页端不提供 Android 精确闹钟、系统通知与使用情况访问等系统级引导。',
            color: scheme.error,
            isLimited: true,
          ),
          const SizedBox(height: 12),
          _buildCapabilityTile(
            icon: Icons.desktop_windows_outlined,
            title: '桌面原生能力不可用',
            subtitle: 'Windows 悬浮窗、托盘、Island、Tai 数据库读取和系统窗口控制仅在桌面端提供。',
            color: scheme.error,
            isLimited: true,
          ),
          const SizedBox(height: 12),
          _buildCapabilityTile(
            icon: Icons.widgets_outlined,
            title: '移动端小组件不可用',
            subtitle: 'Android 桌面小部件、手环同步和原生分享入口不在网页版引导中展示。',
            color: scheme.error,
            isLimited: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMacFeaturePage() {
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.desktop_mac_rounded,
            iconColor: scheme.primary,
            title: 'macOS 原生桌面体验',
            subtitle: '把待办和专注状态融入 macOS：菜单栏、桌面小组件与系统级状态显示随时可用。',
          ),
          const SizedBox(height: 28),
          _buildCapabilityTile(
            icon: Icons.menu_open_rounded,
            title: '菜单栏与灵动岛状态显示',
            subtitle: '专注期间可在 macOS 菜单栏查看剩余时间；原生状态面板还可展示提醒、待办和媒体信息。',
            color: scheme.primary,
          ),
          const SizedBox(height: 12),
          _buildCapabilityTile(
            icon: Icons.widgets_rounded,
            title: '桌面 WidgetKit 小组件',
            subtitle: '在 macOS 桌面添加待办、倒数日和习惯小组件，快速查看当天的任务与状态。',
            color: scheme.secondary,
          ),
          const SizedBox(height: 12),
          _buildCapabilityTile(
            icon: Icons.rocket_launch_rounded,
            title: '后台运行与系统集成',
            subtitle: '支持开机自启、深度链接和系统通知；关闭主窗口后，正在进行的专注不会中断。',
            color: scheme.tertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool isLimited = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return OptionalLiquidGlassCard(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      highContrast: true,
      tint: color.withValues(alpha: 0.16),
      fallbackDecoration: BoxDecoration(
        color: color.withValues(alpha: isLimited ? 0.07 : 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    if (isLimited)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '暂不支持',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.onSurface.withValues(alpha: 0.64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Android 特性及权限引导 ───────────────────────────────

  Widget _buildAndroidFeaturePage1() {
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.bar_chart_outlined,
            iconColor: Colors.purple,
            title: '屏幕时间统计与时间全览',
            subtitle: '全天候统计你的手机使用情况，智能合并番茄钟与各 App 的使用时长，生成一目了然的时间网格。',
          ),
          _buildMediaAsset(
            'assets/guide_media/android_lock_screen.webp',
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),
          _buildPermissionTile(
            title: '应用使用情况权限',
            subtitle: '用于记录你使用了哪些应用以进行时间分配分析',
            isGranted: _hasUsageStats,
            onRequest: () async {
              await _permissionCoordinator.request(
                AppPermissionKind.usageStats,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidFeaturePage2() {
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.notifications_active_outlined,
            iconColor: Theme.of(context).colorScheme.primary,
            title: '精确保活的通知唤醒',
            subtitle: '不论是日程、倒计时、还是番茄钟，我们确保即使应用在后台，也会准时向您推送提醒。',
          ),
          _buildMediaAsset(
            'assets/guide_media/android_notification.webp',
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),
          _buildPermissionTile(
            title: '通知权限',
            subtitle: '核心功能：用于提醒代办与专属通知栏状态',
            isGranted: _notificationStatus?.isGranted == true,
            onRequest: () async {
              await _permissionCoordinator.request(
                AppPermissionKind.notification,
              );
            },
          ),
          const SizedBox(height: 12),
          _buildPermissionTile(
            title: '精确闹钟权限',
            subtitle: '用于应用在指定秒数准时唤醒推送（如倒数结束）',
            isGranted: _hasExactAlarm,
            onRequest: () async {
              await _permissionCoordinator.request(
                AppPermissionKind.exactAlarm,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMinorModeGuidePage() {
    final scheme = Theme.of(context).colorScheme;
    final ageBand = _minorBirthDate == null
        ? MinorAgeBand.unknown
        : MinorAgeBandSystemMapping.fromBirthDate(_minorBirthDate!);
    final selectedDateLabel = _minorBirthDate == null
        ? '未设置'
        : '${_minorBirthDate!.year.toString().padLeft(4, '0')}-'
              '${_minorBirthDate!.month.toString().padLeft(2, '0')}-'
              '${_minorBirthDate!.day.toString().padLeft(2, '0')}';

    return ValueListenableBuilder<MinorModeState>(
      valueListenable: MinorModeService.instance.stateNotifier,
      builder: (context, state, _) {
        return _buildPageContainer(
          content: Column(
            children: [
              const SizedBox(height: 16),
              _buildStepHeader(
                icon: Icons.shield_outlined,
                iconColor: scheme.primary,
                title: '未成年人模式',
                subtitle: '选择出生日期，自动匹配适龄保护策略。出生日期仅保存在本机，不会上传。',
              ),
              const SizedBox(height: 24),
              OptionalLiquidGlassCard(
                margin: EdgeInsets.zero,
                borderRadius: 12,
                highContrast: true,
                fallbackDecoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: Icon(
                      state.systemEnabled
                          ? Icons.phonelink_lock_outlined
                          : Icons.cake_outlined,
                      color: scheme.primary,
                    ),
                    title: Text(state.systemEnabled ? '已跟随手机系统开启' : '设置出生日期'),
                    subtitle: Text(
                      state.systemEnabled
                          ? '系统年龄范围：${state.ageBand.label}；由系统管理，应用内无法绕过。'
                          : '用于开启 App 未成年人模式并应用适龄策略',
                    ),
                    trailing: state.systemEnabled
                        ? null
                        : OutlinedButton(
                            onPressed: _minorBirthDateSaving
                                ? null
                                : _pickMinorBirthDate,
                            child: Text(_minorBirthDate == null ? '选择' : '修改'),
                          ),
                  ),
                ),
              ),
              if (!state.systemEnabled) ...[
                const SizedBox(height: 16),
                AppSettingsSection(
                  title: '当前选择',
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.calendar_month_outlined,
                        color: scheme.primary,
                      ),
                      title: const Text('出生日期'),
                      trailing: Text(
                        selectedDateLabel,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.groups_2_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                      title: const Text('年龄段'),
                      trailing: Text(
                        ageBand.label,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OptionalLiquidGlassCard(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  borderRadius: 12,
                  highContrast: true,
                  tint: scheme.primary.withValues(alpha: 0.16),
                  fallbackDecoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _minorBirthDate == null
                        ? '可以跳过，之后在 设置 > 未成年人模式 中补充。'
                        : ageBand == MinorAgeBand.adult
                        ? '当前年龄段为成人，App 未成年人模式不会开启。'
                        : '当前年龄段为${ageBand.label}，App 未成年人模式已按年龄策略准备。',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── 新增：Android 桌面小部件引导 ──────────────────────────

  Widget _buildAndroidWidgetGuidePage() {
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.widgets_outlined,
            iconColor: Colors.indigo,
            title: '桌面小部件',
            subtitle: '无需打开应用，直接在桌面查看今日课程、待办任务与番茄钟状态。',
          ),
          _buildMediaAsset('assets/guide_media/android_widget_guide.webm'),
          const SizedBox(height: 20),

          // 🚀 一键添加到桌面按钮 (Android 8.0+)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                try {
                  // 调用 MethodChannel (对应 MainActivity.kt 中的 requestPinWidget)
                  final result = await _featureGuidePlatform.invokeMethod(
                    'requestPinWidget',
                  );
                  if (result == false && mounted) {
                    AppSnackBars.showSnackBar(
                      context,
                      const SnackBar(
                        content: Text('您的系统/启动器不支持一键添加，请按下方步骤手动添加'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    AppSnackBars.showSnackBar(
                      context,
                      const SnackBar(content: Text('自动添加失败，请手动添加')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.add_to_home_screen_rounded),
              label: const Text(
                '一键添加到桌面',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 手动步骤说明卡片
          OptionalLiquidGlassCard(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            borderRadius: 14,
            highContrast: true,
            tint: Colors.indigo.withValues(alpha: 0.16),
            fallbackDecoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.indigo.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: Colors.indigo.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '若一键添加失败，可手动添加',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildWidgetStep(
                  '1',
                  '长按手机桌面空白处',
                  Icons.touch_app_rounded,
                  Colors.indigo,
                ),
                const SizedBox(height: 8),
                _buildWidgetStep(
                  '2',
                  '点击「小部件」或「Widget」选项',
                  Icons.grid_view_rounded,
                  Colors.indigo,
                ),
                const SizedBox(height: 8),
                _buildWidgetStep(
                  '3',
                  '找到本应用，选择想要的小部件样式',
                  Icons.search_rounded,
                  Colors.indigo,
                ),
                const SizedBox(height: 8),
                _buildWidgetStep(
                  '4',
                  '拖拽到合适位置，松手即完成添加',
                  Icons.open_with_rounded,
                  Colors.indigo,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 提示条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Colors.indigo.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '部分国产 ROM（如 MIUI、ColorOS）需在「负一屏」或「桌面设置」中单独开启小部件功能。',
                    style: TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 桌面小部件引导的单步骤行
  Widget _buildWidgetStep(
    String stepNum,
    String desc,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            stepNum,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 16, color: color.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            desc,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }

  // ── Windows 特性及配置引导 ──────────────────────────────

  Widget _buildWinFeaturePage1() {
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.timer_outlined,
            iconColor: Colors.redAccent,
            title: '全端番茄钟与大屏专注',
            subtitle: '在 Windows 桌面端享受沉浸式或浮窗式的番茄钟体验。而且，现在支持跨屏自动无缝流转同步！',
          ),
          _buildMediaAsset('assets/guide_media/windows_pomodoro.webm'),
        ],
      ),
    );
  }

  Widget _buildWinFeaturePage2() {
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.web_asset_rounded,
            iconColor: Theme.of(context).colorScheme.secondary,
            title: '无缝接入 Windows 屏幕时间',
            subtitle: '利用本地读取 Tai 软件（专业 Windows 时间追踪应用）的数据库，轻松在应用内部汇总双端时长。',
          ),
          _buildMediaAsset('assets/guide_media/windows_screen_time.webm'),
        ],
      ),
    );
  }
}
