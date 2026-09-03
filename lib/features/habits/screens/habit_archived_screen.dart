import '../../../widgets/floating_glass_control.dart';
import '../../../widgets/management_page.dart';
import 'package:flutter/material.dart';

import '../../../utils/page_transitions.dart';
import '../models/habit_goal.dart';
import '../repositories/habit_repository.dart';
import '../widgets/habit_format.dart';
import 'habit_detail_screen.dart';

/// 已归档习惯列表：归档只隐藏日常入口，不删除习惯和历史记录。
class HabitArchivedScreen extends StatefulWidget {
  const HabitArchivedScreen({super.key, this.loadGoals, this.restoreGoal});

  final Future<List<HabitGoal>> Function()? loadGoals;
  final Future<void> Function(HabitGoal)? restoreGoal;

  @override
  State<HabitArchivedScreen> createState() => _HabitArchivedScreenState();
}

class _HabitArchivedScreenState extends State<HabitArchivedScreen> {
  List<HabitGoal> _goals = [];
  final Map<String, GlobalKey> _cardKeys = {};
  bool _loading = true;
  bool _loadFailed = false;
  String? _restoring;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final goals = await (widget.loadGoals ?? HabitRepository.getGoals)();
      if (!mounted) return;
      setState(() {
        _goals =
            goals.where((goal) => goal.isArchived && !goal.isDeleted).toList();
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  GlobalKey _cardKeyFor(HabitGoal goal) {
    return _cardKeys.putIfAbsent(goal.uuid, GlobalKey.new);
  }

  Future<void> _openDetail(HabitGoal goal) async {
    final changed = await PageTransitions.pushFromRect(
      context: context,
      page: HabitDetailScreen(goal: goal),
      sourceKey: _cardKeyFor(goal),
      placeholderBuilder: (_) => Text(
        goal.icon.isNotEmpty ? goal.icon : '🎯',
        style: const TextStyle(fontSize: 30),
      ),
      sourceBorderRadius: BorderRadius.circular(16),
    );
    if (changed == true && mounted) {
      await _loadData();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _restore(HabitGoal goal) async {
    if (_restoring != null) return;
    setState(() => _restoring = goal.uuid);
    try {
      if (widget.restoreGoal != null) {
        await widget.restoreGoal!(goal);
      } else {
        await HabitRepository.setArchived(goal, false);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('恢复失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _restoring = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final visible = _goals
        .where((goal) => goal.name.toLowerCase().contains(query))
        .toList();
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('已归档习惯'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ManagementPage(maxWidth: 840, children: [
                const ManagementIntro(
                    icon: Icons.inventory_2_outlined,
                    title: '暂时收起，随时继续',
                    description: '归档只隐藏日常入口，习惯与历史记录仍会保留。恢复后可继续追踪。'),
                if (_loadFailed) ...[
                  ManagementLoadError(
                      title: '暂时无法加载习惯',
                      description: '请稍后重试，已保存的记录不会受影响。',
                      onRetry: _loadData),
                ] else ...[
                  ManagementSearchField(
                      controller: _searchController,
                      hintText: '搜索已归档习惯',
                      onChanged: (_) => setState(() {})),
                  const SizedBox(height: 16),
                  Text('已归档 · ${_goals.length}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    ManagementEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: query.isEmpty ? '暂无已归档习惯' : '没有找到匹配的习惯',
                        description: query.isEmpty
                            ? '不再需要每日追踪的习惯，可以先归档在这里。'
                            : '试试其他名称，或清空搜索。'),
                  ...visible.map((goal) => _buildGoalTile(goal, scheme)),
                ],
              ]),
            ),
    );
  }

  Widget _buildGoalTile(HabitGoal goal, ColorScheme scheme) {
    final busy = _restoring == goal.uuid;
    return ManagementCard(
      key: _cardKeyFor(goal),
      borderRadius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12)),
              child: Text(goal.icon.isNotEmpty ? goal.icon : '🎯',
                  style: const TextStyle(fontSize: 24))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(goal.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(HabitText.sourceTypeLabel(goal.sourceType),
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ])),
        ]),
        const SizedBox(height: 12),
        ManagementActionBar(children: [
          TextButton.icon(
              onPressed: _restoring != null ? null : () => _openDetail(goal),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('查看详情')),
          FilledButton.tonalIcon(
              onPressed: _restoring != null ? null : () => _restore(goal),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.unarchive_outlined, size: 18),
              label: Text(busy ? '恢复中…' : '恢复习惯')),
        ]),
      ]),
    );
  }
}
