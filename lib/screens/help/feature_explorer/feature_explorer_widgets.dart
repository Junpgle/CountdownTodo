part of '../feature_explorer_screen.dart';

extension _FeatureExplorerWidgets on _FeatureExplorerScreenState {
  Widget _buildTopControlCard({
    required ColorScheme scheme,
    required List<FeatureExplorerItem> catalog,
    required int totalCount,
    required int exploredCount,
    required int remainingCount,
    required int unreadNewCount,
  }) {
    final progress = totalCount == 0 ? 1.0 : exploredCount / totalCount;
    return RepaintBoundary(
      key: const ValueKey<String>('feature_top_control'),
      child: OptionalLiquidGlassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        borderRadius: 18,
        tint: scheme.primary.withValues(alpha: 0.08),
        fallbackDecoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：探索进度标题 + 已体验 / 还差多少项徽章
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    remainingCount == 0
                        ? Icons.emoji_events_rounded
                        : Icons.explore_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '功能探索进度',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(progress * 100).round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        remainingCount == 0
                            ? '恭喜！你已体验完全部 $totalCount 项功能与隐藏神技'
                            : '共 $totalCount 项能力，点条目看教程，打开对应功能界面才算「已体验」',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 第二行：直观数据指标卡（已体验 X 项 / 还差 Y 项 / 近期新增未读 Z 项）
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '已体验 $exploredCount 项',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey<String>(
                        'feature-explorer-toggle-unexplored-btn',
                      ),
                      borderRadius: BorderRadius.circular(10),
                      onTap: remainingCount > 0
                          ? () {
                              _mutateState(() {
                                _onlyUnexplored = !_onlyUnexplored;
                              });
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _onlyUnexplored
                              ? scheme.tertiaryContainer
                              : scheme.surfaceContainerHighest.withValues(
                                  alpha: 0.6,
                                ),
                          borderRadius: BorderRadius.circular(10),
                          border: _onlyUnexplored
                              ? Border.all(color: scheme.tertiary, width: 1.2)
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              remainingCount == 0
                                  ? Icons.verified_rounded
                                  : (_onlyUnexplored
                                        ? Icons.filter_alt_rounded
                                        : Icons.pending_actions_rounded),
                              size: 15,
                              color: _onlyUnexplored
                                  ? scheme.onTertiaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                remainingCount == 0
                                    ? '还差 0 项'
                                    : (_onlyUnexplored
                                          ? '正筛选未体验($remainingCount)'
                                          : '还差 $remainingCount 项 (点此筛选)'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _onlyUnexplored
                                      ? scheme.onTertiaryContainer
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 第三行：进度条 + 快捷恢复首页清单
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            ),
            const SizedBox(height: 10),
            _buildSearchField(scheme),
            const SizedBox(height: 10),
            _buildCategoryBar(scheme, catalog, unreadNewCount),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFeatureListWidgets(
    List<FeatureExplorerItem> items,
    ColorScheme scheme,
  ) {
    final isAllWithoutSearch =
        _selectedCategory == FeatureExplorerCategory.all &&
        _searchQuery.trim().isEmpty;

    if (!isAllWithoutSearch) {
      final headerTitle = _searchQuery.trim().isNotEmpty
          ? '搜索结果'
          : _selectedCategory.label;
      final headerIcon = _searchQuery.trim().isNotEmpty
          ? Icons.manage_search_rounded
          : _selectedCategory.icon;
      final accent = _categoryAccentColor(_selectedCategory, scheme);
      return [
        _buildUnifiedSectionCard(
          scheme: scheme,
          icon: headerIcon,
          title: headerTitle,
          accentColor: accent,
          items: items,
        ),
      ];
    }

    // 「全部」筛选下：
    // 1. 首先置顶展示「近期新增 · 未读」分组卡片
    // 2. 其余功能按自然模块分类（时间与日程、专注与复盘、成长与生活、AI 与多端、隐藏神技）聚合展示
    final unreadNew = <FeatureExplorerItem>[];
    final byCategory = <FeatureExplorerCategory, List<FeatureExplorerItem>>{};

    for (final item in items) {
      if (item.isNew && !_seenBadges.contains(item.id)) {
        unreadNew.add(item);
      } else {
        byCategory.putIfAbsent(item.category, () => []).add(item);
      }
    }

    final widgets = <Widget>[];

    if (unreadNew.isNotEmpty) {
      widgets.add(
        _buildUnifiedSectionCard(
          scheme: scheme,
          icon: Icons.fiber_new_rounded,
          title: '近期新增 · 未读',
          accentColor: scheme.primary,
          highlightBorder: true,
          isUnreadNewSection: true,
          items: unreadNew,
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }

    const domainCategories = [
      FeatureExplorerCategory.schedule,
      FeatureExplorerCategory.focus,
      FeatureExplorerCategory.growth,
      FeatureExplorerCategory.aiAndSync,
      FeatureExplorerCategory.hiddenTips,
    ];

    for (final category in domainCategories) {
      final categoryItems = byCategory[category];
      if (categoryItems == null || categoryItems.isEmpty) continue;
      widgets.add(
        _buildUnifiedSectionCard(
          scheme: scheme,
          icon: category.icon,
          title: category.label,
          accentColor: _categoryAccentColor(category, scheme),
          items: categoryItems,
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }

    if (widgets.isNotEmpty && widgets.last is SizedBox) {
      widgets.removeLast();
    }

    return widgets;
  }

  /// 与「帮助与反馈」「设置中心」一脉相承的聚合分组卡片，头部直观显示本组已体验/剩余数
  Widget _buildUnifiedSectionCard({
    required ColorScheme scheme,
    required IconData icon,
    required String title,
    required Color accentColor,
    required List<FeatureExplorerItem> items,
    bool highlightBorder = false,
    bool isUnreadNewSection = false,
  }) {
    final exploredInGroup = items
        .where((i) => _seenBadges.contains(i.id))
        .length;
    final remainingInGroup = items.length - exploredInGroup;

    return RepaintBoundary(
      key: ValueKey<String>('feature_section_$title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: accentColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isUnreadNewSection)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '待体验 ${items.length} 项',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: remainingInGroup == 0
                          ? scheme.primaryContainer.withValues(alpha: 0.6)
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      remainingInGroup == 0
                          ? '已全部体验 (${items.length}/${items.length})'
                          : '已体验 $exploredInGroup/${items.length} · 还差 $remainingInGroup 项',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: remainingInGroup == 0
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: highlightBorder
                    ? accentColor.withValues(alpha: 0.45)
                    : scheme.outlineVariant.withValues(alpha: 0.65),
                width: highlightBorder ? 1.2 : 1.0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 66,
                      endIndent: 14,
                      color: scheme.outlineVariant.withValues(alpha: 0.55),
                    ),
                  _buildFeatureRow(items[i], scheme),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return TextField(
      key: const ValueKey<String>('feature-explorer-search-field'),
      controller: _searchController,
      onChanged: (value) => _mutateState(() => _searchQuery = value),
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: '搜索功能、入口或口语词（如：调休、补录、记账、语音、手环）',
        hintStyle: TextStyle(
          fontSize: 13,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  _mutateState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildCategoryBar(
    ColorScheme scheme,
    List<FeatureExplorerItem> catalog,
    int unreadNewCount,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: FeatureExplorerCategory.values.map((category) {
          final selected = _selectedCategory == category;
          final showNewDot =
              category == FeatureExplorerCategory.recent && unreadNewCount > 0;
          final categoryItems = switch (category) {
            FeatureExplorerCategory.all => catalog,
            FeatureExplorerCategory.recent =>
              catalog.where((e) => e.isNew).toList(),
            _ => catalog.where((e) => e.category == category).toList(),
          };
          final exploredInCat = categoryItems
              .where((e) => _seenBadges.contains(e.id))
              .length;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                category.icon,
                size: 15,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${category.label} $exploredInCat/${categoryItems.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (showNewDot) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$unreadNewCount',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheme.onError,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onSelected: (_) {
                _mutateState(() => _selectedCategory = category);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 单行功能条目：左侧语义色图标（带未读红点或已体验角标）+ 中部标题/简介/路径 + 右侧直达胶囊
  Widget _buildFeatureRow(FeatureExplorerItem item, ColorScheme scheme) {
    final isExplored = _seenBadges.contains(item.id);
    final isUnreadNew = item.isNew && !isExplored;
    final accent = _categoryAccentColor(item.category, scheme);

    return InkWell(
      key: ValueKey<String>('feature-explorer-card-${item.id}'),
      onTap: () => _showItemDetailSheet(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧带未读红点或已体验对勾的分类色图标
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isExplored ? 0.08 : 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    item.icon,
                    color: isExplored ? accent.withValues(alpha: 0.65) : accent,
                    size: 20,
                  ),
                ),
                if (isUnreadNew)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.surfaceContainerLow,
                          width: 1.5,
                        ),
                      ),
                    ),
                  )
                else if (isExplored)
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.surfaceContainerLow,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 10,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // 中部：标题 + 标签 + 已体验状态、单行精炼说明、直观入口路径
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: isExplored
                                ? scheme.onSurface.withValues(alpha: 0.78)
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (item.badgeText != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: item.isNew
                                ? accent.withValues(alpha: 0.14)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.badgeText!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: item.isNew
                                  ? accent
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isExplored
                              ? scheme.primaryContainer.withValues(alpha: 0.55)
                              : scheme.tertiaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          isExplored ? '已体验' : '待体验',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: isExplored
                                ? scheme.onPrimaryContainer
                                : scheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 13,
                        color: accent.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          item.locationPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accent.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // 右侧：一键直达按钮 + 详情箭头
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey<String>('feature-explorer-try-${item.id}'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => _launchFeature(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isExplored
                        ? scheme.surfaceContainerHighest.withValues(alpha: 0.65)
                        : accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isExplored ? '再看看' : '去试试',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isExplored ? scheme.onSurfaceVariant : accent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 44,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            _searchQuery.trim().isNotEmpty
                ? '没有找到匹配「$_searchQuery」的功能'
                : '当前筛选下没有待体验的功能',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _searchController.clear();
              _mutateState(() {
                _searchQuery = '';
                _onlyUnexplored = false;
                _selectedCategory = FeatureExplorerCategory.all;
              });
            },
            child: const Text('重置筛选条件'),
          ),
        ],
      ),
    );
  }
}
