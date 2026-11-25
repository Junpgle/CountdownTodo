import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/app_dialogs.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_drink_log_service.dart';
import '../services/habit_rule_resolver.dart';
import '../utils/habit_emoji_utils.dart';
import 'habit_emoji_picker_dialog.dart';
import 'habit_emoji_text.dart';

/// 戒掉饮料类习惯的「今天喝了什么」快捷选择面板。
///
/// 支持多选（例如同一天既喝了 🧋 奶茶 又喝了 🥤 饮料），
/// 同时支持自定义常用饮品图标与名称并自动云同步。
class HabitDrinkPickerSheet extends StatefulWidget {
  final HabitGoal goal;
  final List<HabitGoalRuleRevision> rules;
  final DateTime logicalDate;
  final String username;
  final List<String>? initialSelectedIcons;
  final VoidCallback? onChanged;

  const HabitDrinkPickerSheet({
    super.key,
    required this.goal,
    required this.rules,
    required this.logicalDate,
    this.username = '',
    this.initialSelectedIcons,
    this.onChanged,
  });

  static Future<List<String>?> show({
    required BuildContext context,
    required HabitGoal goal,
    required List<HabitGoalRuleRevision> rules,
    required DateTime logicalDate,
    String username = '',
    List<String>? initialSelectedIcons,
    VoidCallback? onChanged,
  }) {
    final screenSize = MediaQuery.sizeOf(context);
    return showAppModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: screenSize.height * 0.82,
      ),
      builder: (_) => HabitDrinkPickerSheet(
        goal: goal,
        rules: rules,
        logicalDate: logicalDate,
        username: username,
        initialSelectedIcons: initialSelectedIcons,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<HabitDrinkPickerSheet> createState() => _HabitDrinkPickerSheetState();
}

class _HabitDrinkPickerSheetState extends State<HabitDrinkPickerSheet> {
  List<HabitDrinkOption> _options = HabitDrinkLogService.defaultOptions();
  final Set<String> _selectedIcons = <String>{};
  final Set<String> _busyIds = <String>{};
  bool _noDrinkSuccess = false;
  bool _busyNoDrink = false;
  bool _loading = true;
  bool _clearing = false;
  bool _manageMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedIcons != null) {
      _selectedIcons.addAll(widget.initialSelectedIcons!);
    }
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final optionsFuture = HabitDrinkLogService.getOptions();
      final dayKey = HabitRuleResolver.dayKey(widget.logicalDate);
      final checkInsFuture = HabitRepository.getCheckIns(
        habitUuid: widget.goal.uuid,
        fromDate: dayKey,
        toDate: dayKey,
      );
      final options = await optionsFuture;
      final checkIns = await checkInsFuture;
      if (!mounted) return;
      final drinkIcons = HabitDrinkLogService.extractDrinkIcons(checkIns);
      final noDrink = HabitDrinkLogService.hasNoDrinkSuccess(
        widget.goal,
        checkIns,
      );
      setState(() {
        _options = options;
        _selectedIcons
          ..clear()
          ..addAll(drinkIcons);
        _noDrinkSuccess = noDrink;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reloadOptions() async {
    final options = await HabitDrinkLogService.getOptions();
    if (!mounted) return;
    setState(() => _options = options);
  }

  Future<void> _toggleNoDrinkSuccess() async {
    if (_busyNoDrink || _clearing) return;
    HapticFeedback.selectionClick();
    setState(() => _busyNoDrink = true);
    try {
      final next = await HabitDrinkLogService.setNoDrinkSuccessForDay(
        goal: widget.goal,
        rules: widget.rules,
        logicalDate: widget.logicalDate,
        success: !_noDrinkSuccess,
        username: widget.username,
      );
      if (!mounted) return;
      setState(() {
        _noDrinkSuccess = next;
        if (next) {
          _selectedIcons.clear();
        }
      });
      widget.onChanged?.call();
    } finally {
      if (mounted) {
        setState(() => _busyNoDrink = false);
      }
    }
  }

  Future<void> _toggleOption(HabitDrinkOption option) async {
    if (_busyIds.contains(option.uuid) || _clearing || _busyNoDrink) return;
    HapticFeedback.selectionClick();
    setState(() => _busyIds.add(option.uuid));
    try {
      final selected = await HabitDrinkLogService.toggleDrinkForDay(
        goal: widget.goal,
        rules: widget.rules,
        logicalDate: widget.logicalDate,
        option: option,
      );
      if (!mounted) return;
      setState(() {
        if (selected) {
          _noDrinkSuccess = false;
          _selectedIcons.add(option.icon);
        } else {
          _selectedIcons.remove(option.icon);
        }
      });
      widget.onChanged?.call();
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(option.uuid));
      }
    }
  }

  Future<void> _clearAll() async {
    if (_clearing || _selectedIcons.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _clearing = true);
    try {
      await HabitDrinkLogService.clearDrinksForDay(
        goal: widget.goal,
        logicalDate: widget.logicalDate,
      );
      if (!mounted) return;
      setState(() => _selectedIcons.clear());
      widget.onChanged?.call();
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final restored = await HabitDrinkLogService.resetToDefaults(
      username: widget.username,
    );
    if (!mounted) return;
    setState(() {
      _options = restored;
      _manageMode = false;
    });
    widget.onChanged?.call();
  }

  Future<void> _openOptionEditor({HabitDrinkOption? editing}) async {
    final action =
        await showAppDialog<({String type, String icon, String label})>(
          context: context,
          builder: (_) => _HabitDrinkOptionEditorDialog(editing: editing),
        );
    if (action == null || !mounted) return;

    if (action.type == 'delete' && editing != null) {
      await HabitDrinkLogService.deleteOption(
        editing,
        username: widget.username,
      );
      await _reloadOptions();
      widget.onChanged?.call();
      return;
    }

    if (action.type == 'save') {
      if (editing == null) {
        await HabitDrinkLogService.addOption(
          icon: action.icon,
          label: action.label,
          username: widget.username,
        );
      } else {
        await HabitDrinkLogService.updateOption(
          editing,
          icon: action.icon,
          label: action.label,
          username: widget.username,
        );
      }
      await _reloadOptions();
      widget.onChanged?.call();
    }
  }

  List<String> _orderedSelectedIcons() {
    final ordered = <String>[];
    for (final option in _options) {
      if (_selectedIcons.contains(option.icon) &&
          !ordered.contains(option.icon)) {
        ordered.add(option.icon);
      }
    }
    for (final icon in _selectedIcons) {
      if (!ordered.contains(icon)) {
        ordered.add(icon);
      }
    }
    return ordered;
  }

  List<String> _resultIconsForClose() {
    if (_noDrinkSuccess) {
      final fallback = widget.goal.icon.trim().isNotEmpty
          ? widget.goal.icon.trim()
          : '🎯';
      return <String>[fallback];
    }
    return _orderedSelectedIcons();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isToday =
        widget.logicalDate.year == now.year &&
        widget.logicalDate.month == now.month &&
        widget.logicalDate.day == now.day;
    final weekdayChar = '一二三四五六日'[widget.logicalDate.weekday - 1];
    final dateLabel =
        '${widget.logicalDate.month} 月 ${widget.logicalDate.day} 日 · 周$weekdayChar';
    final selectedList = _orderedSelectedIcons();

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
                      Text(
                        isToday
                            ? '${widget.goal.name} · 今日记录'
                            : '${widget.goal.name} · $dateLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      HabitEmojiText(
                        _manageMode
                            ? '点击任意饮品可编辑或删除，修改自动云同步'
                            : _noDrinkSuccess
                            ? '打卡成功 · 今日未喝饮料'
                            : selectedList.isNotEmpty
                            ? '打卡失败（破戒）：${selectedList.join(' ')}'
                            : '没喝点上方打卡成功；喝了则在下方选择饮品',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _noDrinkSuccess
                              ? colorScheme.tertiary
                              : selectedList.isNotEmpty
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _manageMode
                      ? () => setState(() => _manageMode = false)
                      : () => Navigator.of(context).pop(_resultIconsForClose()),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _manageMode ? '完成管理' : '完成',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (!_manageMode) ...[
                _buildNoDrinkSuccessBanner(colorScheme, isToday: isToday),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _manageMode ? '常用饮品图标（轻点编辑或删除）' : '破戒了？选择喝了什么（记为打卡失败）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_manageMode)
                    TextButton(
                      onPressed: _resetToDefaults,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                    )
                  else ...[
                    if (selectedList.isNotEmpty)
                      TextButton(
                        onPressed: _clearing ? null : _clearAll,
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('清空', style: TextStyle(fontSize: 12)),
                      ),
                    TextButton.icon(
                      onPressed: () => setState(() => _manageMode = true),
                      icon: const Icon(Icons.tune_rounded, size: 14),
                      label: const Text('管理', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: _options.length + 1,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 124,
                    mainAxisExtent: 90,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    if (index == _options.length) {
                      return _buildAddTile(colorScheme);
                    }
                    return _buildOptionTile(_options[index], colorScheme);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoDrinkSuccessBanner(
    ColorScheme colorScheme, {
    required bool isToday,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busyNoDrink ? null : _toggleNoDrinkSuccess,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _noDrinkSuccess
                ? colorScheme.tertiaryContainer
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _noDrinkSuccess
                  ? colorScheme.tertiary
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
              width: _noDrinkSuccess ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _noDrinkSuccess
                      ? colorScheme.tertiary.withValues(alpha: 0.16)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _noDrinkSuccess
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 22,
                  color: _noDrinkSuccess
                      ? colorScheme.tertiary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday ? '今日没喝（打卡成功）' : '这一天没喝（打卡成功）',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: _noDrinkSuccess
                            ? colorScheme.onTertiaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _noDrinkSuccess ? '已达标！再次点击可撤销' : '守住没喝饮料，点此计入达标',
                      style: TextStyle(
                        fontSize: 12,
                        color: _noDrinkSuccess
                            ? colorScheme.tertiary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_busyNoDrink)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.tertiary,
                  ),
                )
              else if (_noDrinkSuccess)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '已达标',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(HabitDrinkOption option, ColorScheme colorScheme) {
    final isSelected = _selectedIcons.contains(option.icon);
    final isBusy = _busyIds.contains(option.uuid);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isBusy
            ? null
            : () {
                if (_manageMode) {
                  _openOptionEditor(editing: option);
                } else {
                  _toggleOption(option);
                }
              },
        onLongPress: isBusy ? null : () => _openOptionEditor(editing: option),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: !_manageMode && isSelected
                ? colorScheme.errorContainer.withValues(alpha: 0.72)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _manageMode
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : isSelected
                  ? colorScheme.error
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: !_manageMode && isSelected ? 1.6 : 1,
            ),
          ),
          child: Stack(
            children: [
              if (_manageMode)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                )
              else if (isSelected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.cancel_rounded,
                    size: 15,
                    color: colorScheme.error,
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
                    Text(
                      option.icon,
                      style: const TextStyle(fontSize: 28, height: 1.1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: !_manageMode && isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
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

  Widget _buildAddTile(ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openOptionEditor(),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
              width: 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 26, color: colorScheme.primary),
                const SizedBox(height: 6),
                Text(
                  '自定义',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HabitDrinkOptionEditorDialog extends StatefulWidget {
  final HabitDrinkOption? editing;

  const _HabitDrinkOptionEditorDialog({this.editing});

  @override
  State<_HabitDrinkOptionEditorDialog> createState() =>
      _HabitDrinkOptionEditorDialogState();
}

class _HabitDrinkOptionEditorDialogState
    extends State<_HabitDrinkOptionEditorDialog> {
  late final TextEditingController _iconController;
  late final TextEditingController _labelController;
  late String _selectedIcon;
  String? _iconError;

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.editing?.icon ?? '🍋';
    _iconController = TextEditingController(text: _selectedIcon);
    _labelController = TextEditingController(text: widget.editing?.label ?? '');
  }

  @override
  void dispose() {
    _iconController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _openFullEmojiPicker() async {
    final picked = await HabitEmojiPickerDialog.show(
      context,
      initialIcon: _selectedIcon.isNotEmpty ? _selectedIcon : '🍋',
      initialCategory: HabitEmojiCategory.foodAndDrink,
      title: '选择饮品图标',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedIcon = picked;
      _iconController.text = picked;
      _iconError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final editing = widget.editing;
    return AlertDialog(
      title: Text(editing == null ? '新增常用饮品' : '编辑饮品图标'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: TextField(
                    key: const ValueKey('drink-option-icon-input'),
                    controller: _iconController,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22),
                    decoration: InputDecoration(
                      labelText: '图标',
                      errorText: _iconError,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      final composing = _iconController.value.composing;
                      if (composing.isValid && !composing.isCollapsed) {
                        return;
                      }
                      if (value.trim().isEmpty) {
                        setState(() => _iconError = null);
                        return;
                      }
                      final extracted = HabitEmojiUtils.extractSingleEmoji(
                        value,
                      );
                      setState(() {
                        if (extracted != null) {
                          _selectedIcon = extracted;
                          _iconError = null;
                        } else {
                          _iconError = '请输入 1 个 Emoji';
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _labelController,
                    autofocus: editing == null,
                    decoration: const InputDecoration(
                      labelText: '饮品名称',
                      hintText: '例如：柠檬茶、生椰拿铁',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '选择图标',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('drink-more-emoji-button'),
                  onPressed: _openFullEmojiPicker,
                  icon: const Icon(Icons.emoji_emotions_outlined, size: 16),
                  label: const Text('全部 Emoji'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final emoji in HabitDrinkLogService.suggestedIcons)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _selectedIcon = emoji;
                        _iconController.text = emoji;
                        _iconError = null;
                      });
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _selectedIcon == emoji
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedIcon == emoji
                              ? colorScheme.primary
                              : Colors.transparent,
                          width: 1.4,
                        ),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (editing != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .pop((type: 'delete', icon: '', label: '')),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text('删除'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final rawIcon = _iconController.text.trim();
            final icon = rawIcon.isEmpty
                ? (_selectedIcon.isNotEmpty ? _selectedIcon : null)
                : HabitEmojiUtils.extractSingleEmoji(rawIcon);
            if (icon == null) {
              setState(() => _iconError = '请输入 1 个 Emoji');
              return;
            }
            final label = _labelController.text.trim();
            if (label.isEmpty) return;
            Navigator.of(context).pop((type: 'save', icon: icon, label: label));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
