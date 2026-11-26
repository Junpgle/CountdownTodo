part of '../habit_edit_screen.dart';

String _formatTargetValue(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString();
}

extension _HabitEditTargetStep on _HabitEditScreenState {
  // ── 第 3 步：目标 ────────────────────────────────────
  Widget _buildTargetStep() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '目标设置',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        switch (_sourceType) {
          HabitSourceType.recurringTodo => () {
            final adaptation = HabitAdaptationService.forDraft(
              sourceType: _sourceType,
              name: _nameController.text,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (adaptation != null) ...[
                  HabitAdaptationPanel(
                    adaptation: adaptation,
                    showTargetSuggestions: false,
                  ),
                  const SizedBox(height: 14),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '完成型习惯：每天在待办中完成一次即可。提醒由关联的循环待办触发。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          }(),
          HabitSourceType.pomodoroTag => _buildDurationTarget(colorScheme),
          HabitSourceType.durationCheckIn => _buildDurationTarget(colorScheme),
          HabitSourceType.quantityCheckIn => _buildQuantityTarget(colorScheme),
          HabitSourceType.timeCheckIn => _buildTimeTarget(colorScheme),
        },
        if (widget.goal != null) ...[
          const SizedBox(height: 20),
          Text(
            '规则生效时间',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _effectiveFromChip('today', '从今天开始', '关闭旧规则，新规则从今天生效'),
          _effectiveFromChip(
            'nextPeriod',
            '从下一个周期开始',
            '如每周习惯从下周一、每月习惯从下月 1 号开始',
          ),
          _effectiveFromChip('all', '应用到全部历史', '覆盖所有历史版本的目标值（不改变历史打卡记录）'),
        ],
      ],
    );
  }

  Widget _effectiveFromChip(String option, String title, String subtitle) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _effectiveFromOption == option;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _mutateState(() => _effectiveFromOption = option),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? colorScheme.primary : colorScheme.outline,
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
                        subtitle,
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

  Widget _buildDurationTarget(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind == HabitAdaptationKind.reading) {
      return _buildReadingTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.learning) {
      return _buildLearningTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.meditation) {
      return _buildMeditationTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.sleepDuration) {
      return _buildSleepDurationTarget(colorScheme, adaptation);
    }
    return _buildGenericDurationTarget(colorScheme);
  }

  Widget _buildSleepDurationTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    final targetHours = (_targetMinutes / 60).clamp(1, 16).toDouble();
    final targetLabel = _targetMinutes % 60 == 0
        ? '${_targetMinutes ~/ 60} 小时'
        : '${_targetMinutes ~/ 60} 小时 ${_targetMinutes % 60} 分钟';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: targetHours,
          targetUnitOverride: '小时',
          onTargetSelected: (hours) =>
              _mutateState(() => _targetMinutes = hours * 60),
        ),
        const SizedBox(height: 14),
        Text(
          '睡眠时长会由早睡与早起打卡自动生成；在历史记录中编辑即可手动修正。',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              '每晚目标',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              targetLabel,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        LiquidGlassSlider(
          value: _targetMinutes.toDouble().clamp(6 * 60, 12 * 60),
          min: 6 * 60,
          max: 12 * 60,
          divisions: 12,
          label: targetLabel,
          onChanged: (value) =>
              _mutateState(() => _targetMinutes = value.round()),
        ),
      ],
    );
  }

  Widget _buildGenericDurationTarget(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '目标时长',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '$_targetMinutes 分钟',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        LiquidGlassSlider(
          value: _targetMinutes.toDouble(),
          min: 5,
          max: 240,
          divisions: 47,
          label: '$_targetMinutes 分钟',
          onChanged: (v) => _mutateState(() => _targetMinutes = v.round()),
        ),
        const SizedBox(height: 18),
        Text(
          '开始专注时的默认时长',
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
          children: [5, 10, 15, 20, 25, 30, 45, 50, 60].map((minutes) {
            final selected = _defaultFocusMinutes == minutes;
            return ChoiceChip(
              label: Text('$minutes 分钟'),
              selected: selected,
              onSelected: (_) =>
                  _mutateState(() => _defaultFocusMinutes = minutes),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          '绑定专注标签（可多选）',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (_tags.isEmpty)
          Text(
            '暂无标签，可先在专注页创建标签后再回来绑定',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) {
              final selected = _selectedTagUuids.contains(tag.uuid);
              return FilterChip(
                avatar: _TagColorDot(color: _parseTagColor(tag.color)),
                label: Text(tag.name),
                selected: selected,
                onSelected: (on) => _mutateState(() {
                  if (on) {
                    _selectedTagUuids.add(tag.uuid);
                  } else {
                    _selectedTagUuids.remove(tag.uuid);
                  }
                }),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        Text(
          '使用番茄钟专注时选择对应的习惯标签，时长将自动累计。',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Color _parseTagColor(String hex) => AppColorUtils.parseHex(hex);

  Widget _buildReadingTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    final targetMinutes = _targetMinutes > 0 ? _targetMinutes : 30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: targetMinutes.toDouble(),
          targetUnitOverride: '分钟',
          onTargetSelected: _applyReadingTarget,
        ),
        const SizedBox(height: 14),
        HabitReadingGuide(
          targetMinutes: targetMinutes,
          defaultFocusMinutes: _defaultFocusMinutes,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
        ),
        const SizedBox(height: 14),
        _buildGenericDurationTarget(colorScheme),
      ],
    );
  }

  Widget _buildLearningTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    final targetMinutes = _targetMinutes > 0 ? _targetMinutes : 45;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: targetMinutes.toDouble(),
          targetUnitOverride: '分钟',
          onTargetSelected: _applyLearningTarget,
        ),
        const SizedBox(height: 14),
        HabitLearningGuide(
          targetMinutes: targetMinutes,
          defaultFocusMinutes: _defaultFocusMinutes,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
        ),
        const SizedBox(height: 14),
        _buildGenericDurationTarget(colorScheme),
      ],
    );
  }

  Widget _buildMeditationTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    final targetMinutes = _targetMinutes > 0 ? _targetMinutes : 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: targetMinutes.toDouble(),
          targetUnitOverride: '分钟',
          onTargetSelected: _applyMeditationTarget,
        ),
        const SizedBox(height: 14),
        HabitMeditationGuide(
          targetMinutes: targetMinutes,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
        ),
        const SizedBox(height: 14),
        _buildGenericDurationTarget(colorScheme),
      ],
    );
  }

  Widget _buildQuantityTarget(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind == HabitAdaptationKind.pushUp) {
      return _buildPushUpTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.running) {
      return _buildRunningTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.hydration) {
      return _buildHydrationTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.vocabulary) {
      return _buildVocabularyTarget(colorScheme, adaptation);
    }
    final parsedTarget = double.tryParse(_targetController.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (adaptation != null) ...[
          HabitAdaptationPanel(
            adaptation: adaptation,
            targetValue: parsedTarget,
            onTargetSelected: _applyAdaptationTarget,
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '目标数量',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: '单位（如 ml、个）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '快捷增加（逗号分隔，最多 4 个）',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _quickValuesController,
          onChanged: (v) => _quickValuesText = v,
          decoration: const InputDecoration(
            hintText: '如：250,500',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildHydrationTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    _ensureHydrationDefaults(adaptation);
    final value = (int.tryParse(_targetController.text.trim()) ?? 1600).clamp(
      500,
      4000,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          showTargetSuggestions: false,
        ),
        const SizedBox(height: 14),
        HabitWaterTargetPicker(value: value, onChanged: _applyAdaptationTarget),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '快捷打卡会使用 200 / 300 / 500 ml，方便按杯量快速记录。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVocabularyTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    _ensureVocabularyDefaults(adaptation);
    final parsedTarget = int.tryParse(_targetController.text.trim()) ?? 30;
    final unit = _unitController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: parsedTarget.toDouble(),
          targetUnitOverride: unit,
          onTargetSelected: _applyAdaptationTarget,
        ),
        const SizedBox(height: 14),
        HabitVocabularyGuide(
          targetValue: parsedTarget,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
          unit: unit,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _periodType == HabitPeriodType.weekly
                      ? '每周单词目标'
                      : '每日单词目标',
                  suffixText: unit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: '单位',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '快捷增加（逗号分隔，最多 4 个）',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _quickValuesController,
          onChanged: (v) => _quickValuesText = v,
          decoration: const InputDecoration(
            hintText: '如：10,20,30',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPushUpTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    _ensurePushUpDefaults(adaptation);
    final parsedTarget = int.tryParse(_targetController.text.trim()) ?? 24;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: parsedTarget.toDouble(),
          onTargetSelected: _applyAdaptationTarget,
        ),
        const SizedBox(height: 14),
        HabitPushUpGuide(targetValue: parsedTarget, periodType: _periodType),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '每次训练目标',
                  suffixText: '个',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: '单位',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '快捷增加（逗号分隔，最多 4 个）',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _quickValuesController,
          onChanged: (v) => _quickValuesText = v,
          decoration: const InputDecoration(
            hintText: '如：8,12,16',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildRunningTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    _ensureRunningDefaults(adaptation);
    final parsedTarget = int.tryParse(_targetController.text.trim()) ?? 30;
    final unit = _unitController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: parsedTarget.toDouble(),
          targetUnitOverride: unit,
          onTargetSelected: _applyAdaptationTarget,
        ),
        const SizedBox(height: 14),
        HabitRunningGuide(
          targetValue: parsedTarget,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
          unit: unit,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _periodType == HabitPeriodType.weekly
                      ? '每周运动量'
                      : '每次跑步目标',
                  suffixText: unit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: '单位（建议分钟）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '快捷增加（逗号分隔，最多 4 个）',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _quickValuesController,
          onChanged: (v) => _quickValuesText = v,
          decoration: const InputDecoration(
            hintText: '如：20,30,45',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  void _ensureHydrationDefaults(HabitAdaptation adaptation) {
    if (_targetController.text.trim().isEmpty) {
      _targetController.text = '1600';
    }
    if (_unitController.text.trim().isEmpty) {
      _unitController.text = 'ml';
    }
    if (_quickValuesController.text.trim().isEmpty) {
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    }
  }

  void _ensurePushUpDefaults(HabitAdaptation adaptation) {
    if (_targetController.text.trim().isEmpty) {
      _targetController.text = '24';
    }
    if (_unitController.text.trim().isEmpty) {
      _unitController.text = adaptation.targetUnit;
    }
    if (_quickValuesController.text.trim().isEmpty) {
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    }
  }

  void _ensureRunningDefaults(HabitAdaptation adaptation) {
    if (_targetController.text.trim().isEmpty) {
      _targetController.text = '30';
    }
    if (_unitController.text.trim().isEmpty) {
      _unitController.text = adaptation.targetUnit;
    }
    if (_quickValuesController.text.trim().isEmpty) {
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    }
  }

  void _ensureVocabularyDefaults(HabitAdaptation adaptation) {
    if (_targetController.text.trim().isEmpty) {
      _targetController.text = '30';
    }
    if (_unitController.text.trim().isEmpty) {
      _unitController.text = adaptation.targetUnit;
    }
    if (_quickValuesController.text.trim().isEmpty) {
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    }
  }

  void _applyAdaptationTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation == null) return;
    _mutateState(() {
      _targetController.text = target.toString();
      _unitController.text = adaptation.targetUnit;
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    });
  }

  void _applyReadingTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind != HabitAdaptationKind.reading) return;
    _mutateState(() {
      _targetMinutes = target;
      if (_defaultFocusMinutes == null || _defaultFocusMinutes! > target) {
        _defaultFocusMinutes = target >= 25 ? 25 : target;
      }
    });
  }

  void _applyLearningTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind != HabitAdaptationKind.learning) return;
    _mutateState(() {
      _targetMinutes = target;
      if (_defaultFocusMinutes == null || _defaultFocusMinutes! > target) {
        _defaultFocusMinutes = target >= 25 ? 25 : target;
      }
    });
  }

  void _applyMeditationTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind != HabitAdaptationKind.meditation) return;
    _mutateState(() {
      _targetMinutes = target;
      if (_defaultFocusMinutes == null || _defaultFocusMinutes! > target) {
        _defaultFocusMinutes = target >= 10 ? 10 : target;
      }
    });
  }

  void _applyTimeAdaptationTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation == null) return;
    _mutateState(() {
      _targetTime = TimeOfDay(hour: (target ~/ 60) % 24, minute: target % 60);
      _timeTargetCustomized = true;
      _timeComparison = HabitTimeComparison.before;
      if (adaptation.kind == HabitAdaptationKind.earlySleep) {
        _crossMidnightBoundary = true;
      }
    });
  }

  void _applyTimePairSuggestion(int target) {
    _mutateState(() {
      _targetTime = TimeOfDay(hour: (target ~/ 60) % 24, minute: target % 60);
      _timeTargetCustomized = true;
      _timeComparison = HabitTimeComparison.before;
      _toleranceMinutes = 15;
      final adaptation = HabitAdaptationService.forDraft(
        sourceType: _sourceType,
        name: _nameController.text,
      );
      _crossMidnightBoundary =
          adaptation?.kind == HabitAdaptationKind.earlySleep;
      _reminderEnabled = true;
      _nearEndReminder = true;
    });
  }

  Widget _buildTimeTarget(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    final isSleepAdaptation =
        adaptation?.kind == HabitAdaptationKind.earlyWake ||
        adaptation?.kind == HabitAdaptationKind.earlySleep;
    final pairSuggestion = widget.goal == null
        ? _sleepPairSuggestionFor(adaptation)
        : null;
    final timeText = AppTimeFormats.hourMinute(
      _targetTime.hour,
      _targetTime.minute,
    );
    final beforeLabel = isSleepAdaptation ? '不晚于 $timeText' : '早于 $timeText';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (adaptation != null && isSleepAdaptation) ...[
          HabitAdaptationPanel(
            adaptation: adaptation,
            targetValue: (_targetTime.hour * 60 + _targetTime.minute)
                .toDouble(),
            onTargetSelected: _applyTimeAdaptationTarget,
          ),
          const SizedBox(height: 14),
          if (pairSuggestion != null) ...[
            HabitSleepPairSuggestionCard(
              suggestion: pairSuggestion,
              currentTargetMinute: _targetTime.hour * 60 + _targetTime.minute,
              onApply: _applyTimePairSuggestion,
            ),
            const SizedBox(height: 14),
          ],
          HabitSleepTimingGuide(
            adaptation: adaptation,
            targetMinute: _targetTime.hour * 60 + _targetTime.minute,
            onTargetChanged: _applyTimeAdaptationTarget,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                adaptation?.kind == HabitAdaptationKind.earlyWake
                    ? '目标起床时间'
                    : adaptation?.kind == HabitAdaptationKind.earlySleep
                    ? '目标入睡时间'
                    : '目标时间',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final picked = await showAppTimePicker(
                  context: context,
                  initialTime: _targetTime,
                );
                if (picked != null && mounted) {
                  _mutateState(() {
                    _targetTime = picked;
                    _timeTargetCustomized = true;
                    if (adaptation?.kind == HabitAdaptationKind.earlySleep) {
                      _crossMidnightBoundary = true;
                    }
                  });
                }
              },
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(timeText),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          isSleepAdaptation ? '达标条件（建议使用截止时间）' : '达标条件',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: Text(beforeLabel),
              selected: _timeComparison == HabitTimeComparison.before,
              onSelected: (_) => _mutateState(
                () => _timeComparison = HabitTimeComparison.before,
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('晚于 $timeText'),
              selected: _timeComparison == HabitTimeComparison.after,
              onSelected: (_) => _mutateState(
                () => _timeComparison = HabitTimeComparison.after,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '允许偏差',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextFormField(
                keyboardType: TextInputType.number,
                initialValue: '$_toleranceMinutes',
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n >= 0) _toleranceMinutes = n;
                },
                decoration: const InputDecoration(
                  suffixText: '分钟',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (isSleepAdaptation) ...[
          const SizedBox(height: 8),
          Text(
            '建议先从 15 分钟宽容窗口开始，避免把偶尔的晚睡或晚起直接判定为失败。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [0, 15, 30].map((minutes) {
              return ChoiceChip(
                label: Text('$minutes 分钟'),
                selected: _toleranceMinutes == minutes,
                onSelected: (_) =>
                    _mutateState(() => _toleranceMinutes = minutes),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        LiquidGlassSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('跨午夜习惯（04:00 前算当天）'),
          subtitle: const Text('如早睡：晚上 11 点半打卡，次日 4 点前仍算当天'),
          value: _crossMidnightBoundary,
          onChanged: (v) => _mutateState(() => _crossMidnightBoundary = v),
        ),
      ],
    );
  }

  Widget _buildRecurringTodoBinding(ColorScheme colorScheme) {
    final selectedExists = _recurringTodos.any(
      (todo) =>
          (todo.recurrenceSeriesId ?? todo.id) == _selectedRecurringSeriesId,
    );
    final selectedValue = selectedExists
        ? _selectedRecurringSeriesId
        : _autoCreateRecurringSeries;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '从循环待办导入（可选）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '习惯独立打卡，不再生成循环待办。可选择现有循环待办转入本习惯。',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(selectedValue),
            initialValue: selectedValue,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: _autoCreateRecurringSeries,
                child: Text('不从待办导入（直接作为独立习惯）'),
              ),
              ..._recurringTodos.map((todo) {
                final seriesId = todo.recurrenceSeriesId ?? todo.id;
                return DropdownMenuItem(
                  value: seriesId,
                  child: Text(
                    todo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (value) {
              if (value == null) return;
              _selectRecurringTodo(value);
            },
          ),
          const SizedBox(height: 6),
          Text(
            selectedValue == _autoCreateRecurringSeries
                ? '直接在习惯模块中打卡，漏打卡不会在待办中显示逾期。'
                : '将导入该循环待办的历史期次作为打卡记录，原循环待办系列将移入回收站。',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
