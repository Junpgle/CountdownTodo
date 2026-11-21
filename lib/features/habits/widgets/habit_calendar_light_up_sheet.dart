import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/habit_goal.dart';
import '../services/habit_calendar_light_up_service.dart';
import '../services/habit_drink_log_service.dart';

/// 点击习惯日历某一天时弹出的「快捷点亮图标」面板。
///
/// 用户轻点任意习惯图标即可点亮或取消点亮该日期，
/// 支持同一天连续点亮多个图标（如 🧋 奶茶 + 🥤 饮料）。
class HabitCalendarLightUpSheet extends StatefulWidget {
  final DateTime date;
  final List<HabitGoal> goals;
  final Map<String, bool> initialLitStates;
  final Map<String, List<String>> initialDisplayIconsByHabit;
  final Map<String, String> subtitleByHabit;
  final String? focusedHabitUuid;
  final Future<HabitCalendarToggleResult> Function(
    HabitGoal goal,
    bool currentlyLit,
  )
  onToggleHabit;
  final Future<List<String>?> Function(HabitGoal goal)? onPickDrinks;
  final Future<void> Function()? onCreateHabit;

  const HabitCalendarLightUpSheet({
    super.key,
    required this.date,
    required this.goals,
    required this.initialLitStates,
    this.initialDisplayIconsByHabit = const {},
    required this.subtitleByHabit,
    this.focusedHabitUuid,
    required this.onToggleHabit,
    this.onPickDrinks,
    this.onCreateHabit,
  });

  @override
  State<HabitCalendarLightUpSheet> createState() =>
      _HabitCalendarLightUpSheetState();
}

class _HabitCalendarLightUpSheetState extends State<HabitCalendarLightUpSheet> {
  late final Map<String, bool> _litStates;
  late final Map<String, List<String>> _displayIconsByHabit;
  final Set<String> _busyUuids = <String>{};
  String? _hintMessage;

  @override
  void initState() {
    super.initState();
    _litStates = Map<String, bool>.of(widget.initialLitStates);
    _displayIconsByHabit = {
      for (final entry in widget.initialDisplayIconsByHabit.entries)
        entry.key: List<String>.of(entry.value),
    };
  }

  bool _openingDrinkPicker = false;

  Future<void> _handleTap(HabitGoal goal) async {
    if (_busyUuids.contains(goal.uuid) || _openingDrinkPicker) return;
    HapticFeedback.selectionClick();

    if (HabitDrinkLogService.isDrinkChoiceHabit(goal) &&
        widget.onPickDrinks != null) {
      _openingDrinkPicker = true;
      setState(() => _hintMessage = null);
      try {
        final picked = await widget.onPickDrinks!(goal);
        if (!mounted || picked == null) return;
        setState(() {
          _displayIconsByHabit[goal.uuid] = picked;
          _litStates[goal.uuid] = picked.isNotEmpty;
        });
      } finally {
        _openingDrinkPicker = false;
      }
      return;
    }

    final currentlyLit = _litStates[goal.uuid] ?? false;
    setState(() {
      _busyUuids.add(goal.uuid);
      _hintMessage = null;
    });
    try {
      final result = await widget.onToggleHabit(goal, currentlyLit);
      if (!mounted) return;
      setState(() {
        _litStates[goal.uuid] = result.isLit;
        _hintMessage = result.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hintMessage = '操作失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() => _busyUuids.remove(goal.uuid));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isToday =
        widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
    final weekdayChar = '一二三四五六日'[widget.date.weekday - 1];
    final dateTitle =
        '${widget.date.month} 月 ${widget.date.day} 日 · 周$weekdayChar';
    final litIcons = <String>[];
    for (final goal in widget.goals) {
      if (_litStates[goal.uuid] != true) continue;
      final customIcons = _displayIconsByHabit[goal.uuid];
      if (customIcons != null && customIcons.isNotEmpty) {
        litIcons.addAll(customIcons);
      } else {
        litIcons.add(goal.icon.isNotEmpty ? goal.icon : '🎯');
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            dateTitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '今天',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        litIcons.isEmpty
                            ? '轻点图标即可点亮这一天，支持同时点亮多个'
                            : '已点亮：${litIcons.join(' ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ],
            ),
            if (_hintMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _hintMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (widget.goals.isEmpty)
              _buildEmptyState(colorScheme)
            else
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: widget.goals.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 132,
                    mainAxisExtent: 102,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final goal = widget.goals[index];
                    return _buildHabitTile(goal, colorScheme);
                  },
                ),
              ),
            if (widget.onCreateHabit != null && widget.goals.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await widget.onCreateHabit?.call();
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('新建习惯图标'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🧋 🥤', style: TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(
            '还没有可点亮的习惯',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '新建“喝奶茶”“喝饮料”等习惯后，就能在日历里点亮每一天',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.onCreateHabit != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await widget.onCreateHabit?.call();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('去新建习惯'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHabitTile(HabitGoal goal, ColorScheme colorScheme) {
    final isLit = _litStates[goal.uuid] ?? false;
    final isBusy = _busyUuids.contains(goal.uuid);
    final isFocused = widget.focusedHabitUuid == goal.uuid;
    final isAutoOnly = goal.sourceType == HabitSourceType.pomodoroTag;
    final isDrinkChoice =
        HabitDrinkLogService.isDrinkChoiceHabit(goal) &&
        widget.onPickDrinks != null;
    final customIcons = _displayIconsByHabit[goal.uuid];
    final iconText = (isLit && customIcons != null && customIcons.isNotEmpty)
        ? customIcons.take(2).join()
        : (goal.icon.isNotEmpty ? goal.icon : '🎯');
    final statusText = isAutoOnly
        ? (isLit ? '已点亮' : '专注自动')
        : isDrinkChoice
        ? (isLit ? '已选饮品' : '选喝了啥')
        : (isLit ? '已点亮' : (widget.subtitleByHabit[goal.uuid] ?? '轻点点亮'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isBusy ? null : () => _handleTap(goal),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isLit
                ? colorScheme.primaryContainer.withValues(alpha: 0.78)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLit
                  ? colorScheme.primary
                  : isFocused
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: isLit ? 1.6 : 1,
            ),
          ),
          child: Stack(
            children: [
              if (isLit)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                ),
              if (isBusy)
                Positioned(
                  top: 1,
                  right: 1,
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: isLit ? 1.0 : 0.7,
                      child: Text(
                        iconText,
                        style: const TextStyle(fontSize: 28, height: 1.1),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isLit ? FontWeight.w700 : FontWeight.w600,
                        color: isLit
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isLit
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
