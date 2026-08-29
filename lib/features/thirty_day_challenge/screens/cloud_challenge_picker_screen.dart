import 'package:flutter/material.dart';

import '../models/cloud_challenge.dart';
import '../services/cloud_challenge_service.dart';
import '../../../widgets/floating_bottom_bar.dart';

class CloudChallengePickerScreen extends StatefulWidget {
  const CloudChallengePickerScreen({super.key});

  @override
  State<CloudChallengePickerScreen> createState() =>
      _CloudChallengePickerScreenState();
}

class _CloudChallengePickerScreenState
    extends State<CloudChallengePickerScreen> {
  final _service = CloudChallengeService();
  final _searchController = TextEditingController();
  CloudChallengeCatalog? _catalog;
  Object? _error;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _hasRefreshError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _loadCatalog();
  }

  Future<void> _loadCatalog({bool forceRefresh = false}) async {
    if (_isRefreshing) return;

    setState(() {
      _isLoading = _catalog == null;
      _isRefreshing = true;
      _error = null;
      _hasRefreshError = false;
    });

    CachedCloudChallengeCatalog? cached;
    try {
      cached = await _service.readCachedCatalog();
    } catch (_) {
      // 读取缓存失败时继续走网络请求。
    }

    if (!mounted) return;
    if (cached != null && _catalog == null) {
      setState(() {
        _catalog = cached!.catalog;
        _isLoading = false;
      });
    }

    final shouldRefresh =
        forceRefresh || cached == null || !_service.isCacheFresh(cached);
    if (!shouldRefresh) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      return;
    }

    try {
      final catalog = await _service.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _catalog == null ? error : null;
        _hasRefreshError = _catalog != null;
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  List<CloudChallengeTemplate> _filteredChallenges(
    CloudChallengeCatalog catalog,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return catalog.challenges;

    return catalog.challenges.where((challenge) {
      final searchableText = [
        challenge.id,
        challenge.title,
        challenge.description,
        ...challenge.tags,
        ...challenge.tasks,
      ].join('\n').toLowerCase();
      return searchableText.contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catalog = _catalog;
    final useFloatingBottomBar = floatingBottomBarShouldFloat(context);

    return Scaffold(
      extendBody: useFloatingBottomBar,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('云端挑战'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed:
                _isRefreshing ? null : () => _loadCatalog(forceRefresh: true),
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(scheme)
              : catalog == null
                  ? _buildErrorState(scheme)
                  : _buildCatalog(catalog, scheme),
      bottomNavigationBar: FloatingBottomBar(
        height: 96,
        child: _buildExitAction(scheme),
      ),
    );
  }

  Widget _buildCatalog(CloudChallengeCatalog catalog, ColorScheme scheme) {
    final challenges = _filteredChallenges(catalog);
    final query = _searchController.text.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _buildCustomChallengeCard(scheme),
        const SizedBox(height: 16),
        _buildCatalogHeader(catalog, scheme),
        const SizedBox(height: 20),
        _buildSearchField(scheme),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                '挑一场现在就想开始的挑战',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            Text(
              query.isEmpty
                  ? '${challenges.length} 份'
                  : '${challenges.length}/${catalog.challenges.length} 份',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (challenges.isEmpty)
          _buildEmptySearchState(query, scheme)
        else
          for (final challenge in challenges) ...[
            _buildChallengeCard(challenge, scheme),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: '搜索云端挑战',
        hintText: '输入标题、标签或任务关键词',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清空搜索',
                onPressed: _searchController.clear,
                icon: const Icon(Icons.clear_rounded),
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildEmptySearchState(String query, ColorScheme scheme) {
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 42, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              '没有找到匹配的挑战',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '试试搜索其他标题、标签或任务关键词。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: query.isEmpty ? null : _searchController.clear,
              icon: const Icon(Icons.clear_rounded),
              label: const Text('清空搜索'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogHeader(
    CloudChallengeCatalog catalog,
    ColorScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.cloud_done_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '云端挑战库',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _catalogDescription(catalog),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${catalog.challenges.length} 份挑战 · 支持编辑后开始',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _catalogDescription(CloudChallengeCatalog catalog) {
    if (_isRefreshing) {
      return '正在获取最新清单，当前仍可使用已有内容。';
    }
    if (_hasRefreshError) {
      return '网络更新失败，当前显示上次缓存。选择后会自动填入编辑页，你仍然可以继续修改。';
    }
    if (catalog.updatedAt.isEmpty) {
      return '每天自动检查更新。选择一份挑战后会自动填入编辑页，你仍然可以继续修改。';
    }
    return '清单更新于 ${catalog.updatedAt}。每天自动检查更新，选择后会自动填入编辑页，你仍然可以继续修改。';
  }

  Widget _buildChallengeCard(
    CloudChallengeTemplate challenge,
    ColorScheme scheme,
  ) {
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (challenge.description.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          challenge.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildInfoChip(
                  '${challenge.tasks.length} 项任务',
                  Icons.format_list_bulleted_rounded,
                  scheme,
                ),
                for (final tag in challenge.tags.take(3))
                  _buildInfoChip(tag, Icons.label_outline_rounded, scheme),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '任务预览',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            ...challenge.tasks.take(4).toList().asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.key + 1}',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (challenge.tasks.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '还有 ${challenge.tasks.length - 4} 项任务，开始后可以逐项完成。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectChallenge(
                      challenge,
                      CloudChallengePickerAction.customize,
                    ),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('自定义'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _selectChallenge(
                      challenge,
                      CloudChallengePickerAction.start,
                    ),
                    icon: const Icon(Icons.bolt_rounded),
                    label: const Text('开始挑战'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomChallengeCard(ColorScheme scheme) {
    return Card(
      elevation: 0,
      color: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.edit_note_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '创建自己的挑战',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '不想套用模板？输入文字或导入文件，完全按你的想法开始。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _selectChallenge(
                      null,
                      CloudChallengePickerAction.customize,
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('创建自定义挑战'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSecondaryContainer,
                      side: BorderSide(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectChallenge(
    CloudChallengeTemplate? challenge,
    CloudChallengePickerAction action,
  ) {
    Navigator.of(context).pop(
      CloudChallengePickerResult(
        challenge: challenge,
        action: action,
      ),
    );
  }

  Widget _buildExitAction(ColorScheme scheme) {
    final useFloatingBottomBar = floatingBottomBarShouldFloat(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: useFloatingBottomBar
              ? scheme.surface.withValues(alpha: 0)
              : scheme.surface,
          border: useFloatingBottomBar
              ? null
              : Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.schedule_outlined),
          label: const Text('暂时退出'),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, IconData icon, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '暂时无法获取云端挑战',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '请检查网络连接，或返回使用本地自定义输入。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isRefreshing ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新获取'),
            ),
          ],
        ),
      ),
    );
  }
}
