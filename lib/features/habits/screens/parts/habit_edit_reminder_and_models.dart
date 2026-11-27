part of '../habit_edit_screen.dart';

extension _HabitEditReminderAndPlanning on _HabitEditScreenState {
  // ── 第 4 步：提醒 ────────────────────────────────────
  Widget _buildReminderStep() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_sourceType == HabitSourceType.timeCheckIn) {
      return _buildTimePointReminderStep(colorScheme);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LiquidGlassSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用提醒'),
          value: _reminderEnabled,
          onChanged: (v) => _mutateState(() => _reminderEnabled = v),
        ),
        if (_reminderEnabled) ...[
          Text(
            '固定时间提醒',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final time in _fixedTimes)
                InputChip(
                  label: Text(
                    AppTimeFormats.hourMinute(time.hour, time.minute),
                  ),
                  onDeleted: () => _mutateState(() => _fixedTimes.remove(time)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: const Text('添加'),
                onPressed: () async {
                  if (_fixedTimes.length >= 3) {
                    AppSnackBars.showSnackBar(
                      context,
                      const SnackBar(content: Text('最多添加 3 个提醒时间')),
                    );
                    return;
                  }
                  final picked = await showAppTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 20, minute: 0),
                  );
                  if (picked != null && mounted) {
                    _mutateState(() => _fixedTimes.add(picked));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          LiquidGlassSwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('进度提醒'),
            subtitle: const Text('完成 50% / 100% 时提醒'),
            value: _progressReminder,
            onChanged: (v) => _mutateState(() => _progressReminder = v),
          ),
          LiquidGlassSwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('临近结束提醒'),
            subtitle: const Text('周期快结束时提醒未完成'),
            value: _nearEndReminder,
            onChanged: (v) => _mutateState(() => _nearEndReminder = v),
          ),
          LiquidGlassSwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('当日汇总'),
            subtitle: const Text('每晚汇总当天习惯完成情况'),
            value: _dailySummaryReminder,
            onChanged: (v) => _mutateState(() => _dailySummaryReminder = v),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '提醒设置会保存，并在保存后重新安排通知。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildPlanningAndFocusSection(colorScheme),
      ],
    );
  }

  Widget _buildTimePointReminderStep(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    final title = adaptation?.kind == HabitAdaptationKind.earlySleep
        ? '启用早睡提醒'
        : adaptation?.kind == HabitAdaptationKind.earlyWake
        ? '启用早起提醒'
        : '启用目标提醒';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LiquidGlassSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: const Text('目标前 30 分钟和 5 分钟各提醒一次'),
          value: _nearEndReminder,
          onChanged: (v) => _mutateState(() {
            _reminderEnabled = v;
            _nearEndReminder = v;
          }),
        ),
        if (_reminderEnabled)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '提醒会围绕目标时间安排，不需要额外添加固定时间。${adaptation?.kind == HabitAdaptationKind.earlySleep ? '早睡习惯还会按跨午夜规则归属到前一天。' : ''}',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 12),
        LiquidGlassSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('当日汇总'),
          subtitle: const Text('每晚汇总当天习惯完成情况'),
          value: _dailySummaryReminder,
          onChanged: (v) => _mutateState(() => _dailySummaryReminder = v),
        ),
        Text(
          '提醒是辅助，不代表需要为了赶上目标而牺牲睡眠时长。',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _buildPlanningAndFocusSection(colorScheme),
      ],
    );
  }

  Widget _buildPlanningAndFocusSection(ColorScheme colorScheme) {
    final preferredTimeText = AppTimeFormats.hourMinute(
      _preferredStartTime.hour,
      _preferredStartTime.minute,
    );
    final isPomodoroHabit = _sourceType == HabitSourceType.pomodoroTag;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_view_day_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日容量与专注联动',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '开启后，未完成的习惯会自动作为软时间块计入「今日容量」并展示在日程规划时间轴，避免待办排得过满。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          LiquidGlassSwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('纳入今日容量与规划块'),
            subtitle: const Text('今日未达标时自动预留习惯执行时段'),
            value: _includeInPlanning,
            onChanged: (v) {
              _mutateState(() {
                _includeInPlanning = v;
                if (v && _fixedTimes.isNotEmpty) {
                  _preferredStartTime = _fixedTimes.first;
                }
              });
            },
          ),
          if (_includeInPlanning) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '偏好执行时段',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final picked = await showAppTimePicker(
                      context: context,
                      initialTime: _preferredStartTime,
                    );
                    if (picked != null && mounted) {
                      _mutateState(() => _preferredStartTime = picked);
                    }
                  },
                  icon: const Icon(Icons.schedule_rounded, size: 16),
                  label: Text(preferredTimeText),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '预计耗时（分钟）',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [15, 25, 30, 45, 60].map((minutes) {
                return ChoiceChip(
                  label: Text('$minutes 分钟'),
                  selected: _plannedDurationMinutes == minutes,
                  onSelected: (_) {
                    _mutateState(() {
                      _plannedDurationMinutes = minutes;
                      if (!isPomodoroHabit) {
                        _defaultFocusMinutes = minutes;
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
          if (!isPomodoroHabit) ...[
            const Divider(height: 24),
            LiquidGlassSwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('专注达标后自动完成打卡'),
              subtitle: const Text('从习惯卡片或规划块一键开启番茄钟，专注完成后自动打卡'),
              value: _autoCheckInOnFocus,
              onChanged: (v) => _mutateState(() => _autoCheckInOnFocus = v),
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '关联专注标签（可选）',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags.map((tag) {
                  final selected = _focusTagUuids.contains(tag.uuid);
                  return FilterChip(
                    avatar: _TagColorDot(color: _parseTagColor(tag.color)),
                    label: Text(tag.name),
                    selected: selected,
                    onSelected: (v) {
                      _mutateState(() {
                        if (v) {
                          _focusTagUuids.add(tag.uuid);
                        } else {
                          _focusTagUuids.remove(tag.uuid);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TagColorDot extends StatelessWidget {
  final Color color;

  const _TagColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SleepPairAnchor {
  final String name;
  final HabitAdaptationKind kind;
  final int targetMinute;
  final int updatedAt;

  const _SleepPairAnchor({
    required this.name,
    required this.kind,
    required this.targetMinute,
    required this.updatedAt,
  });
}

enum _HabitCreationMode { template, custom }

class _HabitTemplate {
  final String name;
  final String icon;
  final HabitSourceType type;
  final double targetValue;
  final String unit;
  final List<int> quickValues;
  final int targetTimeMinute;
  final bool crossMidnight;
  final HabitAdaptationKind? adaptationKind;

  const _HabitTemplate(
    this.name,
    this.icon,
    this.type, {
    this.targetValue = 0,
    this.unit = '',
    this.quickValues = const [],
    this.targetTimeMinute = 0,
    this.crossMidnight = false,
    this.adaptationKind,
  });
}
