import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/management_page.dart';

class HistoricalCountdownsScreen extends StatefulWidget {
  final String username;
  final Future<List<CountdownItem>> Function()? loadCountdowns;
  final Future<void> Function(CountdownItem)? deleteCountdown;

  const HistoricalCountdownsScreen({
    super.key,
    required this.username,
    this.loadCountdowns,
    this.deleteCountdown,
  });

  @override
  State<HistoricalCountdownsScreen> createState() =>
      _HistoricalCountdownsScreenState();
}

class _HistoricalCountdownsScreenState
    extends State<HistoricalCountdownsScreen> {
  List<CountdownItem> _history = [];
  final _searchController = TextEditingController();
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _oldestFirst = false;
  String? _deletingId;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() => _isLoading = true);
    try {
      final items = await (widget.loadCountdowns?.call() ??
          StorageService.getCountdowns(widget.username));
      if (!mounted || generation != _loadGeneration) return;
      final now = DateTime.now();
      setState(() {
        // Retain the existing history boundary; this page only changes presentation.
        _history = items
            .where((item) =>
                !item.isDeleted &&
                item.targetDate.difference(now).inDays + 1 < 0)
            .toList()
          ..sort((a, b) => b.targetDate.compareTo(a.targetDate));
        _isLoading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _confirmDelete(CountdownItem item) async {
    if (_deletingId != null) return;
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
        title: const Text('彻底删除这段记录？'),
        content: Text('“${item.title}”将被永久删除，删除后无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError),
              child: const Text('确认删除')),
        ],
      ),
    );
    if (confirm != true || !mounted || _deletingId != null) return;
    setState(() => _deletingId = item.id);
    try {
      if (widget.deleteCountdown != null) {
        await widget.deleteCountdown!(item);
      } else {
        await StorageService.permanentlyDeleteCountdown(
            widget.username, item.id);
      }
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已彻底删除该历史记录')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    var visible = _history
        .where((item) => item.title.toLowerCase().contains(query))
        .toList();
    if (_oldestFirst) visible = visible.reversed.toList();
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('历史倒计时'),
        actions: [
          IconButton(
              tooltip: '刷新',
              onPressed: _isLoading || _deletingId != null ? null : _loadData,
              icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ManagementPage(maxWidth: 900, children: [
                const ManagementIntro(
                    icon: Icons.history_rounded,
                    title: '那些期待过的日子',
                    description: '已结束的倒计时留在这里，方便回顾与整理。'),
                if (_loadFailed) ...[
                  ManagementLoadError(
                      title: '暂时无法加载记录',
                      description: '请重试，已保存的倒计时不会受影响。',
                      onRetry: _loadData),
                ] else ...[
                  ManagementSearchField(
                      controller: _searchController,
                      hintText: '搜索历史倒计时',
                      onChanged: (_) => setState(() {})),
                  const SizedBox(height: 16),
                  ManagementFilterBar<bool>(
                      value: _oldestFirst,
                      onChanged: (value) =>
                          setState(() => _oldestFirst = value),
                      options: [
                        ManagementFilterOption(value: false, label: '最近结束'),
                        ManagementFilterOption(value: true, label: '最早结束')
                      ]),
                  const SizedBox(height: 16),
                  Text(
                      query.isEmpty
                          ? '共 ${_history.length} 段记录'
                          : '找到 ${visible.length} 段记录',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    ManagementEmptyState(
                        icon: Icons.hourglass_empty_rounded,
                        title: query.isEmpty ? '还没有历史倒计时' : '没有找到匹配的记录',
                        description: query.isEmpty
                            ? '倒计时结束后，可以在这里回顾。'
                            : '试试其他关键词，或清空搜索。'),
                  ...visible.map(_buildCard),
                ],
              ]),
            ),
    );
  }

  Widget _buildCard(CountdownItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = (item.targetDate.difference(DateTime.now()).inDays + 1).abs();
    final busy = _deletingId == item.id;
    return ManagementCard(
      key: ValueKey(item.id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.event_available_outlined,
                  color: scheme.onSecondaryContainer)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                    '目标日 · ${DateFormat('yyyy-MM-dd').format(item.targetDate)}',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ])),
        ]),
        const SizedBox(height: 12),
        ManagementActionBar(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('$days 天前结束',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: scheme.primary)),
              TextButton.icon(
                  onPressed:
                      _deletingId != null ? null : () => _confirmDelete(item),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(busy ? '删除中…' : '彻底删除')),
            ]),
      ]),
    );
  }
}
