part of '../about_screen.dart';

extension _AboutScreenCards on _AboutScreenState {
  Widget _buildMemoryCard(BuildContext context, {bool compact = false}) {
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16),
      child: ValueListenableBuilder<MemorySnapshot>(
        valueListenable: AppMemoryMonitor.snapshot,
        builder: (context, snapshot, _) {
          final colorScheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;

          final Color statusColor;
          switch (snapshot.healthLevel) {
            case MemoryHealthLevel.normal:
              statusColor = colorScheme.primary;
              break;
            case MemoryHealthLevel.moderate:
              statusColor = colorScheme.tertiary;
              break;
            case MemoryHealthLevel.high:
              statusColor = colorScheme.error;
              break;
          }

          final isWeb = !snapshot.isProcessMemorySupported;

          return Card(
            elevation: compact ? 0 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: compact
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                : null,
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.memory_rounded,
                        size: compact ? 18 : 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '内存占用与优化',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: compact ? 14 : 15,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '刷新内存数据',
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: () {
                          AppMemoryMonitor.refresh();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '当前占用内存',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                snapshot.healthDescription,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              isWeb
                                  ? snapshot.imageCacheFormatted
                                  : snapshot.currentRssFormatted,
                              style: textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isWeb ? '(图片解码缓存)' : '(物理常驻 RSS)',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (!isWeb && snapshot.maxRss > 0) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: snapshot.peakRatio,
                              minHeight: 6,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '历史峰值: ${snapshot.maxRssFormatted}  •  当前占峰值 ${(snapshot.peakRatio * 100).toStringAsFixed(0)}%',
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!isWeb)
                        _buildPerformanceMetric(
                          context,
                          '物理常驻',
                          snapshot.currentRssFormatted,
                        ),
                      _buildPerformanceMetric(
                        context,
                        '图片解码缓存',
                        snapshot.imageCacheFormatted,
                      ),
                      _buildPerformanceMetric(
                        context,
                        '缓存图片',
                        '${snapshot.imageCacheCount} 张',
                      ),
                      _buildPerformanceMetric(
                        context,
                        '缓存上限',
                        snapshot.maxImageCacheBytesFormatted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        final freed = await AppMemoryMonitor.cleanCache();
                        if (context.mounted) {
                          AppSnackBars.showSnackBar(
                            context,
                            SnackBar(
                              content: Text(
                                freed > 0
                                    ? '已完成内存整理，释放了约 ${AppMemoryMonitor.formatBytes(freed)} 缓存空间'
                                    : '当前图片缓存已处于最低状态，无冗余纹理',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.cleaning_services_rounded,
                        size: 18,
                      ),
                      label: const Text('一键释放图片缓存与内存'),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppMemoryMonitor.isAutoRefreshing,
                    builder: (context, isAuto, _) {
                      return LiquidGlassSwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('实时刷新内存占用'),
                        subtitle: const Text('每 2 秒自动采样，便于观测滑动及操作中的内存变化'),
                        value: isAuto,
                        onChanged: (val) {
                          AppMemoryMonitor.setAutoRefresh(val);
                        },
                      );
                    },
                  ),
                  ValueListenableBuilder<MemoryPolicyMode>(
                    valueListenable: AppMemoryMonitor.policyMode,
                    builder: (context, mode, _) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Text(
                              '缓存策略',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<MemoryPolicyMode>(
                              value: mode,
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(
                                  value: MemoryPolicyMode.balanced,
                                  child: Text('标准平衡 (推荐)'),
                                ),
                                DropdownMenuItem(
                                  value: MemoryPolicyMode.performance,
                                  child: Text('极速流畅 (优先高刷)'),
                                ),
                                DropdownMenuItem(
                                  value: MemoryPolicyMode.eco,
                                  child: Text('紧凑节约 (低内存)'),
                                ),
                              ],
                              onChanged: (newMode) {
                                if (newMode != null) {
                                  AppMemoryMonitor.setPolicyMode(newMode);
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPerformanceCard(BuildContext context) {
    if (!AppPerformanceMonitor.isAvailable) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<int>(
      valueListenable: AppPerformanceMonitor.changes,
      builder: (context, _, _) {
        final monitor = AppPerformanceMonitor.snapshot;
        final colorScheme = Theme.of(context).colorScheme;
        final events = monitor.events.take(8).toList();

        return _buildInfoCard(
          context,
          title: '帧性能测试器（调试）',
          icon: Icons.speed_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidGlassSwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用帧性能记录'),
                subtitle: const Text('仅 Debug/Profile 构建可见，记录超过阈值的帧'),
                value: AppPerformanceMonitor.isEnabled,
                onChanged: AppPerformanceMonitor.setEnabled,
              ),
              if (AppPerformanceMonitor.isEnabled) ...[
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('触发阈值'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: monitor.thresholdMilliseconds,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: AppPerformanceMonitor.availableThresholds
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value ms'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          AppPerformanceMonitor.setThresholdMilliseconds(value);
                        }
                      },
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: AppPerformanceMonitor.clear,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const Text('清空'),
                    ),
                  ],
                ),
                LiquidGlassSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('记录触发界面'),
                  subtitle: const Text('在每条超时帧后显示当前页面名称'),
                  value: AppPerformanceMonitor.isScreenTrackingEnabled,
                  onChanged: AppPerformanceMonitor.setScreenTrackingEnabled,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPerformanceMetric(
                      context,
                      '采样帧',
                      '${monitor.frameCount}',
                    ),
                    _buildPerformanceMetric(
                      context,
                      '超阈值',
                      '${monitor.overThresholdCount}',
                    ),
                    _buildPerformanceMetric(
                      context,
                      '慢构建',
                      '${monitor.slowBuildCount}',
                    ),
                    _buildPerformanceMetric(
                      context,
                      '慢光栅',
                      '${monitor.slowRasterCount}',
                    ),
                    _buildPerformanceMetric(
                      context,
                      '最大耗时',
                      _formatPerformanceDuration(monitor.maxFrameSpan),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('最近触发记录', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (events.isEmpty)
                  Text(
                    monitor.frameCount == 0
                        ? '操作应用中的页面后，这里会显示详细帧耗时。'
                        : '当前采样帧均未超过 ${monitor.thresholdMilliseconds} ms。',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  )
                else
                  ...events.map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatPerformanceTime(event.observedAt)}  ·  ${_formatPerformanceDuration(event.totalSpan)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'build ${_formatPerformanceDuration(event.buildDuration)}  ·  '
                              'raster ${_formatPerformanceDuration(event.rasterDuration)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '触发界面：${event.screen}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildPerformanceMetric(
    BuildContext context,
    String label,
    String value,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label $value'),
    );
  }

  String _formatPerformanceDuration(Duration duration) {
    if (duration == Duration.zero) return '0.0 ms';
    return '${(duration.inMicroseconds / 1000).toStringAsFixed(1)} ms';
  }

  String _formatPerformanceTime(DateTime time) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    String threeDigits(int value) => value.toString().padLeft(3, '0');
    return '${twoDigits(time.hour)}:${twoDigits(time.minute)}:'
        '${twoDigits(time.second)}.${threeDigits(time.millisecond)}';
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
    bool compact = false,
  }) {
    return Card(
      elevation: compact ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: compact
          ? Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3)
          : null,
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: compact ? 18 : 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 14 : 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              key: settingsNavigationKey('privacy'),
              leading: Icon(
                Icons.privacy_tip_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('隐私政策'),
              subtitle: _privacyPolicyDate != null
                  ? Text('版本日期：$_privacyPolicyDate')
                  : const Text('查看我们如何收集、使用和保护您的个人信息'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showPrivacyPolicyPage,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(
                Icons.do_not_disturb_on_outlined,
                color: Colors.orange,
              ),
              title: const Text('撤回隐私同意'),
              subtitle: const Text('撤回后将退出账号并清除本地数据'),
              onTap: _showWithdrawConfirmation,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, {bool compact = false}) {
    return Card(
      elevation: compact ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: compact
          ? Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3)
          : null,
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.devices,
                  size: compact ? 18 : 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '设备信息',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 14 : 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('设备型号', _deviceModel),
            const SizedBox(height: 8),
            _buildInfoRow('操作系统', _osVersion),
            const SizedBox(height: 8),
            _buildInfoRow('CPU 架构', _deviceArch),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  Widget _buildCleanupCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                Icons.cleaning_services_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('数据库清理'),
              subtitle: const Text('剔除重复课程数据，优化数据库体积'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _runDeduplication,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final version = _databaseVersion;
    final versionSubtitle = _databaseVersionLoadFailed
        ? '读取失败，可重试或直接查看架构日志'
        : version == null
        ? '正在读取本地 SQLite 架构版本…'
        : version == DatabaseSchemaHistory.currentVersion
        ? '本地 SQLite 架构已是最新版本'
        : '最新版本为 V${DatabaseSchemaHistory.currentVersion}';

    final Widget versionTrailing;
    if (_databaseVersionLoadFailed) {
      versionTrailing = IconButton(
        onPressed: _loadDatabaseVersion,
        icon: const Icon(Icons.refresh_rounded),
        tooltip: '重新读取',
      );
    } else if (version == null) {
      versionTrailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      versionTrailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'V$version',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.storage_rounded, color: colorScheme.primary),
              title: const Text('当前数据库版本'),
              subtitle: Text(versionSubtitle),
              trailing: versionTrailing,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: Icon(
                Icons.manage_history_rounded,
                color: colorScheme.primary,
              ),
              title: const Text('数据库更新日志'),
              subtitle: Text(
                '查看 V1 至 V${DatabaseSchemaHistory.currentVersion} 的架构变更',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showDatabaseChangelog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkCard(
    BuildContext context, {
    required List<_LinkItem> items,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Column(
              children: [
                ListTile(
                  key: item.sourceKey,
                  leading: Icon(
                    item.icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    item.subtitle,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: item.onTap,
                ),
                if (index < items.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildChangelogCard(BuildContext context) {
    final visibleEntries = _versionExpanded
        ? _changelogEntries
        : _changelogEntries.take(_AboutScreenState._pageSize).toList();
    final hasMore = _versionExpanded
        ? !_archiveLoaded
        : _changelogEntries.length > _AboutScreenState._pageSize;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '更新日志',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (_changelogEntries.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${_changelogEntries.length} 个版本',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              _isLoadingChangelog
                  ? const AppSkeletonSheetList(
                      itemCount: 3,
                      itemHeight: 42,
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(vertical: 8),
                    )
                  : _changelogEntries.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('暂无更新日志'),
                      ),
                    )
                  : Column(
                      children: [
                        ...visibleEntries.map(
                          (entry) => _buildChangelogEntry(entry),
                        ),
                        if (hasMore)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: _isLoadingArchive
                                    ? null
                                    : () {
                                        if (!_versionExpanded) {
                                          // 第一次展开：显示更多近期版本
                                          _mutateState(
                                            () => _versionExpanded = true,
                                          );
                                          // 同时后台加载归档
                                          _loadArchive();
                                        } else if (!_archiveLoaded) {
                                          // 已展开但归档未加载：加载归档
                                          _loadArchive();
                                        }
                                      },
                                icon: _isLoadingArchive
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.expand_more, size: 18),
                                label: Text(
                                  _isLoadingArchive
                                      ? '加载中...'
                                      : _versionExpanded
                                      ? '加载更早版本'
                                      : '查看全部',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChangelogEntry(ChangelogEntry entry) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.versionName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (entry.date.isNotEmpty)
              Text(
                entry.date,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entry.items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(item, style: const TextStyle(fontSize: 13)),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMigrationPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.4),
              colorScheme.secondaryContainer.withValues(alpha: 0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '升级至 Uni-Sync 4.0',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (_migrationCompleted)
                  const Icon(Icons.check_circle, color: Colors.green, size: 24),
              ],
            ),
            const SizedBox(height: 16),
            if (!_isMigrating && !_migrationCompleted) ...[
              Text(
                _migrationErrors.isEmpty
                    ? '您的数据目前存储在旧版引擎中。升级到 Uni-Sync 4.0 (SQLite) 将获得极速搜索、离线同步和更稳定的数据保护。'
                    : '上次迁移有 ${_migrationErrors.length} 条异常，旧数据仍保留。修复问题后可以重试。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: colorScheme.onSurface,
                ),
              ),
              if (_migrationErrors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '成功: $_migrationSuccessCount | 失败: ${_migrationErrors.length}',
                  style: TextStyle(fontSize: 11, color: colorScheme.error),
                ),
                const SizedBox(height: 4),
                Text(
                  _migrationErrors.take(3).join('\n'),
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.error,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startMigration,
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: Text(
                    _migrationErrors.isEmpty ? '立即开始极速迁移' : '重试未完成迁移',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else if (_isMigrating || _migrationCompleted) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _migrationStage,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '成功: $_migrationSuccessCount | 失败: ${_migrationErrors.length}',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _migrationProgress,
                  minHeight: 8,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                ),
              ),
              if (_migrationErrors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: colorScheme.onErrorContainer,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '迁移发现 ${_migrationErrors.length} 条异常',
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _migrationErrors.take(3).join('\n'),
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_migrationErrors.length > 3)
                        Text(
                          '...',
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                    ],
                  ),
                ),
              ],
              if (_migrationCompleted && _migrationErrors.isEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '数据已成功迁移至 SQLite 极速引擎！',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
