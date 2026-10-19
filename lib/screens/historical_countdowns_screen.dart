import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../storage_service.dart';
import '../utils/calendar_date_math.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/management_page.dart';
import '../utils/app_dialogs.dart';

final Map<String?, DateFormat> _historicalCountdownDateFormats = {};

DateFormat _historicalCountdownDateFormat() {
  final locale = Intl.defaultLocale;
  return _historicalCountdownDateFormats.putIfAbsent(
    locale,
    () => DateFormat('yyyy-MM-dd', locale),
  );
}

class HistoricalCountdownsScreen extends StatefulWidget {
  final String username;
  final Future<List<CountdownItem>> Function()? loadCountdowns;
  final Future<void> Function(CountdownItem)? deleteCountdown;
  final DateTime Function()? now;

  const HistoricalCountdownsScreen({
    super.key,
    required this.username,
    this.loadCountdowns,
    this.deleteCountdown,
    this.now,
  });

  @override
  State<HistoricalCountdownsScreen> createState() =>
      _HistoricalCountdownsScreenState();
}

class _HistoricalCountdownsScreenState
    extends State<HistoricalCountdownsScreen> {
  List<CountdownItem> _history = [];
  List<String> _historySearchTitles = const <String>[];
  final _searchController = TextEditingController();
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _oldestFirst = false;
  String? _deletingId;
  int _loadGeneration = 0;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

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
      final items =
          await (widget.loadCountdowns?.call() ??
              StorageService.getCountdowns(widget.username));
      if (!mounted || generation != _loadGeneration) return;
      final today = _now();
      final history =
          items
              .where(
                (item) =>
                    !item.isDeleted &&
                    CalendarDateMath.daysBetween(item.targetDate, today) > 0,
              )
              .toList()
            ..sort((a, b) => b.targetDate.compareTo(a.targetDate));
      final searchTitles = [
        for (final item in history) item.title.toLowerCase(),
      ];
      setState(() {
        // Countdown targets are calendar dates, so avoid elapsed-hour math
        // around daylight-saving transitions.
        _history = history;
        _historySearchTitles = searchTitles;
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
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
        title: const Text('彻底删除这段记录？'),
        content: Text('“${item.title}”将被永久删除，删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: const Text('确认删除'),
          ),
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
          widget.username,
          item.id,
        );
      }
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('已彻底删除该历史记录')),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('删除失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _history
        : [
            for (var index = 0; index < _history.length; index++)
              if (_historySearchTitles[index].contains(query)) _history[index],
          ];
    final topBarHeight = floatingGlassTopBarHeight(context);
    final headerChildren = <Widget>[
      const ManagementIntro(
        icon: Icons.history_rounded,
        title: '那些期待过的日子',
        description: '已结束的倒计时留在这里，方便回顾与整理。',
      ),
      if (_loadFailed) ...[
        ManagementLoadError(
          title: '暂时无法加载记录',
          description: '请重试，已保存的倒计时不会受影响。',
          onRetry: _loadData,
        ),
      ] else ...[
        ManagementSearchField(
          controller: _searchController,
          hintText: '搜索历史倒计时',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        ManagementFilterBar<bool>(
          value: _oldestFirst,
          onChanged: (value) => setState(() => _oldestFirst = value),
          options: [
            ManagementFilterOption(value: false, label: '最近结束'),
            ManagementFilterOption(value: true, label: '最早结束'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          query.isEmpty
              ? '共 ${_history.length} 段记录'
              : '找到 ${visible.length} 段记录',
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          ManagementEmptyState(
            icon: Icons.hourglass_empty_rounded,
            title: query.isEmpty ? '还没有历史倒计时' : '没有找到匹配的记录',
            description: query.isEmpty ? '倒计时结束后，可以在这里回顾。' : '试试其他关键词，或清空搜索。',
          ),
      ],
    ];
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('历史倒计时'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _isLoading || _deletingId != null ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ManagementPage.builder(
                  topPadding: topBarHeight,
                  maxWidth: 900,
                  itemCount: headerChildren.length + visible.length,
                  itemBuilder: (context, index) {
                    if (index < headerChildren.length) {
                      return headerChildren[index];
                    }
                    final visibleIndex = index - headerChildren.length;
                    final recordIndex = _oldestFirst
                        ? visible.length - 1 - visibleIndex
                        : visibleIndex;
                    return _buildCard(visible[recordIndex]);
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildCard(CountdownItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = CalendarDateMath.daysBetween(item.targetDate, _now());
    final busy = _deletingId == item.id;
    final targetDateFormat = _historicalCountdownDateFormat();
    return ManagementCard(
      key: ValueKey(item.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.event_available_outlined,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '目标日 · ${targetDateFormat.format(item.targetDate)}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ManagementActionBar(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                '$days 天前结束',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                ),
              ),
              TextButton.icon(
                onPressed: _deletingId != null
                    ? null
                    : () => _confirmDelete(item),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(busy ? '删除中…' : '彻底删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
