part of '../habit_edit_screen.dart';

const List<_HabitTemplate> _templates = <_HabitTemplate>[
  _HabitTemplate(
    '喝水',
    '💧',
    HabitSourceType.quantityCheckIn,
    targetValue: 1600,
    unit: 'ml',
    quickValues: [200, 300, 500],
    adaptationKind: HabitAdaptationKind.hydration,
  ),
  _HabitTemplate(
    '早起',
    '🌅',
    HabitSourceType.timeCheckIn,
    targetTimeMinute: 7 * 60,
    adaptationKind: HabitAdaptationKind.earlyWake,
  ),
  _HabitTemplate(
    '早睡',
    '🌙',
    HabitSourceType.timeCheckIn,
    targetTimeMinute: 23 * 60 + 30,
    crossMidnight: true,
    adaptationKind: HabitAdaptationKind.earlySleep,
  ),
  _HabitTemplate(
    '睡眠时长',
    '🛌',
    HabitSourceType.durationCheckIn,
    targetValue: 8 * 60 * 60,
    adaptationKind: HabitAdaptationKind.sleepDuration,
  ),
  _HabitTemplate('每日签到', '✅', HabitSourceType.recurringTodo),
  _HabitTemplate(
    '戒掉饮料',
    '🥤',
    HabitSourceType.recurringTodo,
    adaptationKind: HabitAdaptationKind.quitSugaryDrinks,
  ),
  _HabitTemplate(
    '俯卧撑',
    '💪',
    HabitSourceType.quantityCheckIn,
    targetValue: 24,
    unit: '个',
    quickValues: [8, 12, 16],
    adaptationKind: HabitAdaptationKind.pushUp,
  ),
  _HabitTemplate(
    '阅读',
    '📖',
    HabitSourceType.pomodoroTag,
    targetValue: 30 * 60,
    adaptationKind: HabitAdaptationKind.reading,
  ),
  _HabitTemplate('运动', '🏃', HabitSourceType.pomodoroTag, targetValue: 30 * 60),
  _HabitTemplate(
    '学习',
    '📚',
    HabitSourceType.pomodoroTag,
    targetValue: 45 * 60,
    adaptationKind: HabitAdaptationKind.learning,
  ),
  _HabitTemplate(
    '冥想',
    '🧘',
    HabitSourceType.pomodoroTag,
    targetValue: 10 * 60,
    adaptationKind: HabitAdaptationKind.meditation,
  ),
  _HabitTemplate(
    '维生素',
    '💊',
    HabitSourceType.quantityCheckIn,
    targetValue: 1,
    unit: '粒',
    quickValues: [1],
  ),
  _HabitTemplate(
    '整理',
    '🧹',
    HabitSourceType.quantityCheckIn,
    targetValue: 1,
    unit: '次',
    quickValues: [1],
  ),
  _HabitTemplate(
    '单词',
    '🔤',
    HabitSourceType.quantityCheckIn,
    targetValue: 30,
    unit: '个',
    quickValues: [10, 20, 30],
    adaptationKind: HabitAdaptationKind.vocabulary,
  ),
  _HabitTemplate(
    '跑步',
    '🏃',
    HabitSourceType.quantityCheckIn,
    targetValue: 30,
    unit: '分钟',
    quickValues: [20, 30, 45],
    adaptationKind: HabitAdaptationKind.running,
  ),
];

extension _HabitEditCreationAndTypeSteps on _HabitEditScreenState {
  // ── 第 1 步：模板 / 手动自定义 ─────────────────────────
  Widget _buildCreationStep() {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.goal != null) {
      return _buildIdentityEditor(
        colorScheme,
        title: '基本信息',
        subtitle: '编辑习惯名称和图标；习惯类型保持不变。',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '从哪里开始？',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '先确定习惯的起点，下一步再设置类型、周期和目标。',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _creationModeCard(
          mode: _HabitCreationMode.template,
          title: '从模板创建',
          subtitle: '直接获得合适的类型、目标和快捷操作，再按需调整。',
          icon: Icons.auto_awesome_rounded,
        ),
        _creationModeCard(
          mode: _HabitCreationMode.custom,
          title: '手动自定义',
          subtitle: '从空白开始，自己决定习惯名称、类型、周期和目标。',
          icon: Icons.tune_rounded,
        ),
        if (_creationMode != null) ...[
          const SizedBox(height: 20),
          if (_creationMode == _HabitCreationMode.template)
            _buildTemplatePicker(colorScheme),
          const SizedBox(height: 16),
          _buildIdentityEditor(
            colorScheme,
            title: _creationMode == _HabitCreationMode.template
                ? '确认基本信息'
                : '自定义基本信息',
            subtitle: _creationMode == _HabitCreationMode.template
                ? '模板已经填好默认值，名称和图标仍可修改。'
                : '给习惯起一个清楚的名字，之后再选择类型与周期。',
          ),
        ],
      ],
    );
  }

  Widget _creationModeCard({
    required _HabitCreationMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _creationMode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            if (selected) return;
            if (mode == _HabitCreationMode.custom) {
              _startCustomCreation();
            } else {
              _mutateState(() {
                _creationMode = mode;
                _selectedTemplateName = null;
              });
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.chevron_right_rounded,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTemplatePicker(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '选择一个模板',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (_selectedTemplateName != null)
              Text(
                '已选：$_selectedTemplateName',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _orderedTemplates.map((template) {
              final isSelected = _selectedTemplateName == template.name;
              return SizedBox(
                width: 104,
                child: Material(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => _applyTemplate(template),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 82,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(
                                  alpha: 0.55,
                                ),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            template.icon,
                            style: const TextStyle(fontSize: 26),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            template.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityEditor(
    ColorScheme colorScheme, {
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                maxLength: 20,
                onChanged: _handleNameChanged,
                decoration: const InputDecoration(
                  labelText: '习惯名称',
                  hintText: '如：喝水、早起、阅读',
                  border: OutlineInputBorder(),
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _buildIconPicker(),
          ],
        ),
        if (widget.goal != null &&
            _sourceType == HabitSourceType.recurringTodo &&
            _selectedRecurringSeriesId != _autoCreateRecurringSeries) ...[
          const SizedBox(height: 8),
          Text(
            '已从关联循环待办带入名称和图标，可按需修改。',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
        if (widget.goal == null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _creationMode == _HabitCreationMode.template
                ? _startCustomCreation
                : () => _mutateState(() {
                    _creationMode = _HabitCreationMode.template;
                    _selectedTemplateName = null;
                  }),
            icon: Icon(
              _creationMode == _HabitCreationMode.template
                  ? Icons.tune_rounded
                  : Icons.auto_awesome_rounded,
            ),
            label: Text(
              _creationMode == _HabitCreationMode.template
                  ? '改为手动自定义'
                  : '改为从模板创建',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildIconPicker() {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: const ValueKey('habit-edit-icon-picker'),
      onTap: () => _showIconDialog(),
      borderRadius: BorderRadius.circular(12),
      child: Tooltip(
        message: '自定义习惯图标',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(_icon, style: const TextStyle(fontSize: 26)),
                ),
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 1.5),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  size: 12,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showIconDialog() async {
    final selected = await HabitEmojiPickerDialog.show(
      context,
      initialIcon: _icon,
      title: '选择习惯图标',
    );
    if (selected != null && mounted) {
      _mutateState(() => _icon = selected);
    }
  }

  // ── 第 1 步：类型与周期 ───────────────────────────────
  Widget _buildTypeStep() {
    final isEdit = widget.goal != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '习惯类型',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (isEdit)
          _typeCard(_sourceType, selected: true, enabled: false)
        else ...[
          _typeCard(
            HabitSourceType.recurringTodo,
            selected: _sourceType == HabitSourceType.recurringTodo,
          ),
          _typeCard(
            HabitSourceType.pomodoroTag,
            selected: _sourceType == HabitSourceType.pomodoroTag,
          ),
          _typeCard(
            HabitSourceType.quantityCheckIn,
            selected: _sourceType == HabitSourceType.quantityCheckIn,
          ),
          _typeCard(
            HabitSourceType.timeCheckIn,
            selected: _sourceType == HabitSourceType.timeCheckIn,
          ),
          _typeCard(
            HabitSourceType.durationCheckIn,
            selected: _sourceType == HabitSourceType.durationCheckIn,
          ),
        ],
        const SizedBox(height: 20),
        _buildPeriodSection(),
        if (_sourceType == HabitSourceType.recurringTodo) ...[
          const SizedBox(height: 20),
          _buildRecurringTodoBinding(colorScheme),
        ],
      ],
    );
  }

  Widget _typeCard(
    HabitSourceType type, {
    bool selected = false,
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final (String title, String desc) = switch (type) {
      HabitSourceType.recurringTodo => ('完成型', '每天完成一次，如打卡签到'),
      HabitSourceType.pomodoroTag => ('时长型', '累计专注时长，如阅读 30 分钟'),
      HabitSourceType.durationCheckIn => ('时长型', '累计独立时长，如每晚睡眠 8 小时'),
      HabitSourceType.quantityCheckIn => ('数量型', '记录累计数量，如饮水量、步数或次数'),
      HabitSourceType.timeCheckIn => ('时间点型', '记录发生时间，如 7 点前起床'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: enabled && selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled
              ? () {
                  _mutateState(() {
                    _sourceType = type;
                    if (type != HabitSourceType.recurringTodo) {
                      _selectedRecurringSeriesId = _autoCreateRecurringSeries;
                    }
                  });
                  _applySleepPairSuggestionIfNeeded();
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled && selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  enabled && selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: enabled && selected
                      ? colorScheme.primary
                      : colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '执行周期',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _periodChip(HabitPeriodType.daily, '每天'),
            _periodChip(HabitPeriodType.weekdays, '工作日'),
            _periodChip(HabitPeriodType.weekly, '每周'),
            _periodChip(HabitPeriodType.monthly, '每月'),
            _periodChip(HabitPeriodType.custom, '自定义'),
          ],
        ),
        if (_periodType == HabitPeriodType.weekdays) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (int i = 0; i < 7; i++)
                ChoiceChip(
                  label: Text(AppTimeFormats.weekdayLabelsZh[i]),
                  selected: (_weekdaysMask & (1 << i)) != 0,
                  onSelected: (on) => _mutateState(() {
                    if (on) {
                      _weekdaysMask |= (1 << i);
                    } else {
                      _weekdaysMask &= ~(1 << i);
                    }
                  }),
                ),
            ],
          ),
        ],
        if (_periodType == HabitPeriodType.custom) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text('每 ', style: TextStyle(color: colorScheme.onSurface)),
              SizedBox(
                width: 64,
                child: TextFormField(
                  keyboardType: TextInputType.number,
                  initialValue: '$_customIntervalDays',
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) _customIntervalDays = n;
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Text(' 天', style: TextStyle(color: colorScheme.onSurface)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _periodChip(HabitPeriodType type, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _periodType == type,
      onSelected: (_) => _mutateState(() => _periodType = type),
    );
  }
}
