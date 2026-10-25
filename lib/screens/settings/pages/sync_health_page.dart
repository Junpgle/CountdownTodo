import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/sync_health_service.dart';
import '../../../utils/settings_navigation.dart';
import '../../../widgets/floating_glass_control.dart';
import '../../conflict_inbox_screen.dart';
import 'course_settings_page.dart';

class SyncHealthPage extends StatefulWidget {
  const SyncHealthPage({
    super.key,
    required this.username,
    this.isEmbedded = false,
  });

  final String username;
  final bool isEmbedded;

  @override
  State<SyncHealthPage> createState() => _SyncHealthPageState();
}

class _SyncHealthPageState extends State<SyncHealthPage> {
  final GlobalKey _conflictNavigationKey = GlobalKey(
    debugLabel: 'sync-health-conflicts',
  );
  final GlobalKey _courseNavigationKey = GlobalKey(
    debugLabel: 'sync-health-courses',
  );

  SyncHealthSnapshot? _snapshot;
  Object? _loadError;
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _showAllModules = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  Future<void> _loadSnapshot({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await SyncHealthService.load(widget.username);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _snapshot = snapshot;
        _loadError = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _retry(Iterable<SyncHealthModule> modules) async {
    final selectedModules = modules.toSet();
    if (selectedModules.isEmpty || _isRetrying) return;
    setState(() => _isRetrying = true);

    final result = await SyncHealthService.retryModules(
      username: widget.username,
      modules: selectedModules,
    );
    if (!mounted) return;
    await _loadSnapshot(showLoading: false);
    if (!mounted) return;
    setState(() => _isRetrying = false);

    final snapshot = _snapshot;
    final message = !result.success
        ? _safeErrorSummary(result.error ?? '同步失败，请稍后重试')
        : snapshot == null
        ? '同步请求已完成'
        : snapshot.totalRetryableCount > 0
        ? '同步请求已完成，仍有 ${snapshot.totalRetryableCount} 项可重试数据'
        : snapshot.totalConflictCount > 0
        ? '同步请求已完成，仍有 ${snapshot.totalConflictCount} 项冲突待核对'
        : '同步请求已完成';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openConflicts() async {
    await SettingsNavigation.push<void>(
      context: context,
      page: ConflictInboxScreen(username: widget.username),
      sourceKey: _conflictNavigationKey,
      isEmbedded: widget.isEmbedded,
      settings: const RouteSettings(name: '同步冲突中心'),
    );
  }

  Future<void> _openCourseSettings() async {
    await SettingsNavigation.push<void>(
      context: context,
      page: const CourseSettingsPage(isEmbedded: false),
      sourceKey: _courseNavigationKey,
      isEmbedded: widget.isEmbedded,
      settings: const RouteSettings(name: '课表设置'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('同步状态'),
              actions: [
                IconButton(
                  tooltip: '刷新状态',
                  onPressed: _isLoading ? null : _loadSnapshot,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final topInset = floatingGlassSettingsContentTopInset(context);
    if (_isLoading && _snapshot == null) {
      return Padding(
        padding: EdgeInsets.only(top: topInset),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null && _snapshot == null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16, topInset, 16, 24),
        children: [
          _buildLoadError(context),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _loadSnapshot(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新读取'),
          ),
        ],
      );
    }

    final snapshot = _snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final attentionModules = snapshot.modules
        .where((module) => module.needsAttention)
        .toList(growable: false);
    final quietModules = snapshot.modules
        .where((module) => !module.needsAttention)
        .toList(growable: false);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () => _loadSnapshot(showLoading: false),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, topInset, 16, 32),
            children: [
              _buildOverviewCard(context, snapshot),
              const SizedBox(height: 16),
              if (_loadError != null) ...[
                _buildLoadError(context),
                const SizedBox(height: 12),
              ],
              if (attentionModules.isNotEmpty) ...[
                _buildSectionHeading(
                  context,
                  '待处理',
                  '${snapshot.totalPendingCount} 项数据 · ${snapshot.totalConflictCount} 项冲突',
                ),
                const SizedBox(height: 8),
                for (final status in attentionModules) ...[
                  _buildModuleCard(context, status),
                  const SizedBox(height: 10),
                ],
              ] else ...[
                _buildAllClearCard(context, snapshot),
                const SizedBox(height: 12),
              ],
              if (quietModules.isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showAllModules = !_showAllModules),
                  icon: Icon(
                    _showAllModules ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(
                    _showAllModules
                        ? '收起无待处理的模块'
                        : '查看 ${quietModules.length} 个无待处理模块',
                  ),
                ),
              if (_showAllModules)
                for (final status in quietModules) ...[
                  _buildModuleCard(context, status),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context, SyncHealthSnapshot snapshot) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = snapshot.totalConflictCount > 0
        ? colorScheme.error
        : snapshot.totalFailedCount > 0
        ? colorScheme.error
        : snapshot.totalRetryableCount > 0
        ? colorScheme.tertiary
        : colorScheme.primary;
    final title = snapshot.totalConflictCount > 0
        ? '有冲突需要核对'
        : snapshot.totalFailedCount > 0
        ? '${snapshot.totalFailedCount} 项同步失败'
        : snapshot.totalRetryableCount > 0
        ? '${snapshot.totalRetryableCount} 项等待同步'
        : snapshot.totalPendingCount > 0
        ? '部分数据仅保存在本机'
        : '同步状态正常';
    final subtitle = snapshot.lastSuccessfulRequestAt == null
        ? '尚无同步请求成功记录'
        : '最近请求成功：${_formatDate(snapshot.lastSuccessfulRequestAt!)}';
    final retryModules = snapshot.modules
        .where((module) => module.canRetry)
        .map((module) => module.module)
        .toSet();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_rounded, color: statusColor, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (snapshot.totalRetryableCount > 0) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isRetrying ? null : () => _retry(retryModules),
                  icon: _isRetrying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(_isRetrying ? '正在安全重试…' : '重试可同步项目'),
                ),
              ),
            ],
            if (snapshot.lastScreenTimeSyncAt != null) ...[
              const SizedBox(height: 8),
              Text(
                '屏幕时间最近同步：${_formatDate(snapshot.lastScreenTimeSyncAt!)}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '请求成功不代表每条记录都已确认；请以各模块的待处理数量为准。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeading(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleCard(BuildContext context, SyncHealthModuleStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLocalOnly =
        status.module == SyncHealthModule.finance && !status.cloudSyncEnabled;
    final summary = isLocalOnly
        ? '本机保留 ${status.localPendingCount} 条 · 云同步未开启'
        : status.pendingCount > 0
        ? '待处理 ${status.pendingCount} 项'
        : status.conflictCount > 0
        ? '冲突待核对 ${status.conflictCount} 项'
        : '当前没有待处理项目';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: status.failedCount > 0 || status.conflictCount > 0,
        leading: Icon(_moduleIcon(status.module), color: colorScheme.primary),
        title: Text(
          status.module.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(summary),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          if (status.conflictCount > 0)
            _buildConflictNotice(context, status.conflictCount),
          if (status.operations.isNotEmpty)
            ...status.operations
                .take(5)
                .map((operation) => _buildOperationRow(context, operation)),
          if (status.operations.length > 5)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '另有 ${status.operations.length - 5} 条操作记录',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (status.module == SyncHealthModule.finance &&
              status.localPendingCount > 0)
            _buildLocalOnlyNotice(context, status),
          if (status.module == SyncHealthModule.screenTime &&
              status.localPendingCount > 0)
            _buildScreenTimeNotice(context, status),
          if (status.module == SyncHealthModule.courses)
            _buildCourseNotice(context),
          if (status.module == SyncHealthModule.other)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                status.module.description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (status.conflictCount > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _openConflicts,
                icon: const Icon(Icons.compare_arrows_rounded),
                label: const Text('前往冲突中心核对'),
              ),
            ),
          ],
          if (status.canRetry) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isRetrying ? null : () => _retry({status.module}),
                icon: const Icon(Icons.sync_rounded),
                label: Text('重试${status.module.label}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConflictNotice(BuildContext context, int count) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count 项版本冲突或缺少冲突快照，需要核对后处理。普通重试不会解决冲突。',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: colorScheme.onErrorContainer),
      ),
    );
  }

  Widget _buildOperationRow(
    BuildContext context,
    SyncHealthOperation operation,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = operation.isVersionConflict
        ? '版本冲突，需要到冲突中心核对'
        : operation.error.isNotEmpty
        ? _safeErrorSummary(operation.error)
        : '等待上传';
    final time = operation.timestamp > 0
        ? _formatDate(DateTime.fromMillisecondsSinceEpoch(operation.timestamp))
        : '时间未知';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        operation.isVersionConflict
            ? Icons.compare_arrows_rounded
            : operation.hasError
            ? Icons.error_outline_rounded
            : Icons.schedule_rounded,
        color: operation.isVersionConflict || operation.hasError
            ? colorScheme.error
            : colorScheme.onSurfaceVariant,
      ),
      title: Text('${_operationLabel(operation.operationType)} · $time'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildLocalOnlyNotice(
    BuildContext context,
    SyncHealthModuleStatus status,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = status.cloudSyncEnabled
        ? '有 ${status.localPendingCount} 条记账数据等待同步。'
        : '云同步已关闭；${status.localPendingCount} 条记录仍安全保存在本机。';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildScreenTimeNotice(
    BuildContext context,
    SyncHealthModuleStatus status,
  ) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      '${status.localPendingCount} 个应用的使用时间等待上传。',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  Widget _buildCourseNotice(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _openCourseSettings,
        icon: const Icon(Icons.school_outlined),
        label: const Text('打开课表设置'),
      ),
    ),
  );

  Widget _buildLoadError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.errorContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _loadError == null
                    ? '暂时无法读取同步状态。'
                    : _safeErrorSummary(_loadError.toString()),
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllClearCard(BuildContext context, SyncHealthSnapshot snapshot) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.primaryContainer.withValues(alpha: 0.46),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                snapshot.lastSuccessfulRequestAt == null
                    ? '目前没有待处理项目。完成一次同步后，这里会显示请求完成时间。'
                    : '目前没有待处理项目，各模块的本地队列为空。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _moduleIcon(SyncHealthModule module) => switch (module) {
    SyncHealthModule.todos => Icons.checklist_rounded,
    SyncHealthModule.countdowns => Icons.event_available_outlined,
    SyncHealthModule.pomodoro => Icons.timer_outlined,
    SyncHealthModule.timeLogs => Icons.history_rounded,
    SyncHealthModule.planBlocks => Icons.calendar_month_outlined,
    SyncHealthModule.fixedSchedules => Icons.event_repeat_outlined,
    SyncHealthModule.habits => Icons.track_changes_outlined,
    SyncHealthModule.finance => Icons.account_balance_wallet_outlined,
    SyncHealthModule.screenTime => Icons.phone_android_rounded,
    SyncHealthModule.courses => Icons.school_outlined,
    SyncHealthModule.other => Icons.cloud_queue_outlined,
  };

  String _operationLabel(String operation) => switch (operation.toUpperCase()) {
    'INSERT' => '新增',
    'UPDATE' => '更新',
    'DELETE' => '删除',
    'UPSERT' => '保存',
    _ => '待同步操作',
  };

  String _formatDate(DateTime date) => DateFormat('M月d日 HH:mm').format(date);

  String _safeErrorSummary(String input) {
    var safe = input.trim();
    safe = safe.replaceAll(
      RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
      'Bearer [已隐藏]',
    );
    safe = safe.replaceAll(
      RegExp(
        r'(token|authorization|password|secret|api[_-]?key)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '[敏感信息已隐藏]',
    );
    if (safe.length > 180) safe = '${safe.substring(0, 180)}…';
    return safe.isEmpty ? '原因未知' : safe;
  }
}
