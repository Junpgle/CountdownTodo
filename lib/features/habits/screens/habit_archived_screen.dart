import 'package:flutter/material.dart';

import '../../../utils/page_transitions.dart';
import '../models/habit_goal.dart';
import '../repositories/habit_repository.dart';
import '../widgets/habit_format.dart';
import 'habit_detail_screen.dart';

/// 已归档习惯列表：归档只隐藏日常入口，不删除习惯和历史记录。
class HabitArchivedScreen extends StatefulWidget {
  const HabitArchivedScreen({super.key});

  @override
  State<HabitArchivedScreen> createState() => _HabitArchivedScreenState();
}

class _HabitArchivedScreenState extends State<HabitArchivedScreen> {
  List<HabitGoal> _goals = [];
  final Map<String, GlobalKey> _cardKeys = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final goals = await HabitRepository.getGoals();
    if (!mounted) return;
    setState(() {
      _goals = goals.where((goal) => goal.isArchived).toList();
      _loading = false;
    });
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
    await HabitRepository.setArchived(goal, false);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('已归档习惯'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
              ? _buildEmpty(colorScheme)
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: _goals.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final goal = _goals[index];
                      return _buildGoalTile(goal, colorScheme);
                    },
                  ),
                ),
    );
  }

  Widget _buildGoalTile(HabitGoal goal, ColorScheme colorScheme) {
    return Container(
      key: _cardKeyFor(goal),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            goal.icon.isNotEmpty ? goal.icon : '🎯',
            style: const TextStyle(fontSize: 24),
          ),
        ),
        title: Text(
          goal.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(HabitText.sourceTypeLabel(goal.sourceType)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '取消归档',
              onPressed: () => _restore(goal),
              icon: Icon(
                Icons.unarchive_outlined,
                color: colorScheme.primary,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        onTap: () => _openDetail(goal),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无已归档习惯',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '归档后的习惯会保留在这里，历史记录不会丢失。',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
