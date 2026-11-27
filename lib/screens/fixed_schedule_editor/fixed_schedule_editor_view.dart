part of '../fixed_schedule_editor_screen.dart';

extension _FixedScheduleEditorView on _FixedScheduleEditorScreenState {
  String _reminderLabel(int minutes) {
    if (minutes == 0) return '开始时';
    if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
    if (minutes % 60 == 0) return '提前 ${minutes ~/ 60} 小时';
    return '提前 $minutes 分钟';
  }

  String _recurrenceLabel(RecurrenceType type) => switch (type) {
    RecurrenceType.none => '不重复',
    RecurrenceType.daily => '每天',
    RecurrenceType.weekly => '每周',
    RecurrenceType.monthly => '每月',
    RecurrenceType.yearly => '每年',
    RecurrenceType.weekdays => '工作日',
    RecurrenceType.customDays => '自定义',
  };

  Widget _buildSquareTile({
    Key? key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: key,
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 100),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.015),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: enabled
                          ? color.withValues(alpha: 0.12)
                          : colors.onSurfaceVariant.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: enabled
                          ? color
                          : colors.onSurfaceVariant.withValues(alpha: 0.4),
                      size: 22,
                    ),
                  ),
                  if (!enabled)
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? colors.onSurface
                          : colors.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupSquareTile<T>({
    Key? key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required T value,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
    bool enabled = true,
  }) {
    return PopupMenuButton<T>(
      key: key,
      initialValue: value,
      enabled: enabled,
      onOpened: _unfocusActiveInput,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: _buildSquareTile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        enabled: enabled,
        onTap: null,
      ),
    );
  }

  Widget _buildEditorScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bgColor = theme.brightness == Brightness.light
        ? const Color(0xFFF2F2F7)
        : colors.surface;
    final topBarHeight = floatingGlassTopBarHeight(context);
    final compactSaveAction =
        MediaQuery.sizeOf(context).width < 390 ||
        MediaQuery.textScalerOf(context).scale(14) > 16;
    final dateText = AppTimeFormats.date(_date);
    final recurrenceEndDateText = AppTimeFormats.date(_recurrenceEndDate);
    final appBarTitle = compactSaveAction
        ? _forcedOccurrenceEdit
              ? '编辑场次'
              : (_editing ? '编辑日程' : '新建日程')
        : _forcedOccurrenceEdit
        ? '编辑当前场次'
        : (_editing &&
                  _seriesItems.where((entry) => !entry.isDeleted).length > 1
              ? '编辑重复日程系列'
              : (_editing ? '编辑固定日程' : '新增固定日程'));

    final selectedTeam = _selectedTeamUuid == null
        ? null
        : _teams.where((team) => team.uuid == _selectedTeamUuid).firstOrNull;
    final selectedTeamName = _selectedTeamUuid == null
        ? '个人私有'
        : (selectedTeam?.name ?? '当前团队');

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: bgColor,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(
          appBarTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_editing)
            IconButton(
              onPressed: _saving || _loadingContext ? null : _delete,
              style: floatingGlassPlainIconButtonStyle(),
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              tooltip: '删除固定日程',
            ),
          if (compactSaveAction)
            IconButton(
              key: const ValueKey('fixed-schedule-save'),
              onPressed: _saving || _loadingContext ? null : _save,
              style: floatingGlassPlainIconButtonStyle(),
              tooltip: '保存',
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            )
          else
            TextButton(
              key: const ValueKey('fixed-schedule-save'),
              onPressed: _saving || _loadingContext ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _unfocusActiveInput,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: FloatingGlassTopBarContentFade(
              topBarHeight: topBarHeight,
              child: AbsorbPointer(
                absorbing: _loadingContext,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, topBarHeight + 8, 16, 32),
                  children: [
                    if (_loadingContext)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_supportsRangeEdit) ...[
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 14),
                        color: colors.primaryContainer.withValues(alpha: 0.35),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: colors.primary.withValues(alpha: 0.15),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.repeat_on_rounded,
                            color: colors.primary,
                          ),
                          title: const Text(
                            '修改范围',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${_scopeLabel(_editScope)} · ${_scopeDescription(_editScope)}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          trailing: const Icon(Icons.expand_more_rounded),
                          onTap: _saving ? null : _chooseEditScope,
                        ),
                      ),
                    ] else if (_forcedOccurrenceEdit) ...[
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 14),
                        color: colors.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: colors.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: const ListTile(
                          leading: Icon(Icons.info_outline_rounded),
                          title: Text(
                            '只编辑当前场次',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('重复范围由外部日历管理，请在来源日历中修改系列规则。'),
                        ),
                      ),
                    ],
                    // 顶部主要信息卡片（标题、地点、备注、已取消）
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: colors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: Colors.black.withValues(alpha: 0.04),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _titleController,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: "日程名称 (例如：算法设计与分析实验)",
                                hintStyle: TextStyle(
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontWeight: FontWeight.normal,
                                  fontSize: 17,
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: colors.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            TextField(
                              controller: _locationController,
                              style: const TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                prefixIcon: Icon(
                                  Icons.location_on_outlined,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                hintText: "地点 (可选)",
                                hintStyle: TextStyle(
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontSize: 15,
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: colors.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            TextField(
                              controller: _remarkController,
                              maxLines: 3,
                              minLines: 1,
                              style: const TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                prefixIcon: Icon(
                                  Icons.notes_rounded,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                hintText: "备注 (可选)",
                                hintStyle: TextStyle(
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontSize: 15,
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                            if (_editing) ...[
                              Divider(
                                height: 1,
                                thickness: 0.8,
                                color: colors.outlineVariant.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                              LiquidGlassSwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _cancelled,
                                onChanged: (value) {
                                  _unfocusActiveInput();
                                  _mutateState(() => _cancelled = value);
                                },
                                secondary: Icon(
                                  _cancelled
                                      ? Icons.event_busy_rounded
                                      : Icons.event_available_rounded,
                                  color: _cancelled
                                      ? Colors.redAccent
                                      : colors.onSurfaceVariant,
                                ),
                                title: Text(
                                  '日程已取消',
                                  style: TextStyle(
                                    color: _cancelled
                                        ? Colors.redAccent
                                        : colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: const Text(
                                  '取消状态只属于当前场次，不受修改范围影响',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // 分组 1：时间与日期
                    Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 12),
                      child: Text(
                        "时间与日期",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: colors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: Colors.black.withValues(alpha: 0.04),
                        ),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            key: const ValueKey('fixed-schedule-date'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.calendar_today_rounded,
                                color: colors.primary,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              _recurrence == RecurrenceType.none
                                  ? '日期'
                                  : (_effectiveEditScope ==
                                            FixedScheduleEditScope.series
                                        ? '首次日期'
                                        : '本次日期'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              _dateWithSemesterWeek(_date, dateText),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '时间待定',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                LiquidGlassSwitch(
                                  key: const ValueKey(
                                    'fixed-schedule-time-tbd',
                                  ),
                                  value: _timeTbd,
                                  onChanged: (value) {
                                    _unfocusActiveInput();
                                    _mutateState(() => _timeTbd = value);
                                  },
                                ),
                              ],
                            ),
                            onTap: _forcedOccurrenceEdit ? null : _pickDate,
                          ),
                          if (!_timeTbd) ...[
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: colors.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            ListTile(
                              key: const ValueKey('fixed-schedule-start-time'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.play_circle_outline_rounded,
                                  color: colors.primary,
                                  size: 20,
                                ),
                              ),
                              title: const Text(
                                '开始时间',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _startTime.format(context),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                              onTap: _pickStartTime,
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: colors.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            ListTile(
                              key: const ValueKey('fixed-schedule-end-time'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrangeAccent.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.stop_circle_outlined,
                                  color: Colors.deepOrangeAccent,
                                  size: 20,
                                ),
                              ),
                              title: const Text(
                                '结束时间',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: _endTimeTbd
                                  ? const Text(
                                      '待定',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    )
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!_endTimeTbd) ...[
                                    Text(
                                      _endTime.format(context),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepOrangeAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    '待定',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  LiquidGlassSwitch(
                                    key: const ValueKey(
                                      'fixed-schedule-end-time-tbd',
                                    ),
                                    value: _endTimeTbd,
                                    onChanged: (value) {
                                      _unfocusActiveInput();
                                      _mutateState(() => _endTimeTbd = value);
                                    },
                                  ),
                                ],
                              ),
                              onTap: _endTimeTbd ? null : _pickEndTime,
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 分组 2：组织与重复
                    Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 12),
                      child: Text(
                        "组织与重复",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildPopupSquareTile<RecurrenceType>(
                            title: '重复规则',
                            subtitle: _recurrenceLabel(_recurrence),
                            icon: Icons.repeat_rounded,
                            color: colors.tertiary,
                            enabled: _canEditRecurrence,
                            value: _recurrence,
                            items: _FixedScheduleEditorScreenState
                                ._supportedRecurrences
                                .map(
                                  (type) => PopupMenuItem(
                                    value: type,
                                    child: Row(
                                      children: [
                                        if (_recurrence == type)
                                          Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color: colors.primary,
                                          )
                                        else
                                          const SizedBox(width: 18),
                                        const SizedBox(width: 8),
                                        Text(_recurrenceLabel(type)),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                            onSelected: (value) {
                              _mutateState(() {
                                _recurrence = value;
                                if (value != RecurrenceType.none &&
                                    !_recurrenceEndDate.isAfter(_date)) {
                                  _recurrenceEndDate =
                                      FixedScheduleRecurrenceService.defaultEndDate(
                                        startDate: _date,
                                        recurrence: value,
                                        customIntervalDays:
                                            int.tryParse(
                                              _customIntervalController.text
                                                  .trim(),
                                            ) ??
                                            1,
                                      );
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildPopupSquareTile<String>(
                            title: '团队归属',
                            subtitle: selectedTeamName,
                            icon: Icons.groups_rounded,
                            color: Colors.indigoAccent,
                            enabled: _canChangeTeam,
                            value: _selectedTeamUuid ?? '',
                            items: [
                              PopupMenuItem<String>(
                                value: '',
                                child: Row(
                                  children: [
                                    if (_selectedTeamUuid == null)
                                      Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: colors.primary,
                                      )
                                    else
                                      const SizedBox(width: 18),
                                    const SizedBox(width: 8),
                                    const Text('个人私有 (仅自己可见)'),
                                  ],
                                ),
                              ),
                              if (_selectedTeamUuid != null &&
                                  !_teams.any(
                                    (team) => team.uuid == _selectedTeamUuid,
                                  ))
                                PopupMenuItem<String>(
                                  value: _selectedTeamUuid!,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('当前团队'),
                                    ],
                                  ),
                                ),
                              ..._teams.map(
                                (team) => PopupMenuItem<String>(
                                  value: team.uuid,
                                  child: Row(
                                    children: [
                                      if (_selectedTeamUuid == team.uuid)
                                        Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: colors.primary,
                                        )
                                      else
                                        const SizedBox(width: 18),
                                      const SizedBox(width: 8),
                                      Text(team.name),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            onSelected: (value) => _mutateState(() {
                              _selectedTeamUuid = value.isEmpty ? null : value;
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (!_canChangeTeam)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '只有日程创建者可以更改团队归属；其他内容仍可协作编辑。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!_canEditRecurrence)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text(
                          '仅修改当前场次，重复规则和其他日期保持不变。',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (_recurrence != RecurrenceType.none &&
                        _canEditRecurrence)
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(top: 12),
                        color: colors.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            children: [
                              if (_recurrence == RecurrenceType.customDays) ...[
                                Row(
                                  children: [
                                    const Text(
                                      "每隔",
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 72,
                                      child: TextField(
                                        controller: _customIntervalController,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 8,
                                                horizontal: 8,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      "天重复",
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                                Divider(
                                  height: 20,
                                  thickness: 0.8,
                                  color: colors.outlineVariant.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ],
                              InkWell(
                                onTap: _pickRecurrenceEndDate,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.event_repeat_rounded,
                                            size: 18,
                                            color: colors.tertiary,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            "重复结束日期",
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            _dateWithSemesterWeek(
                                              _recurrenceEndDate,
                                              recurrenceEndDateText,
                                            ),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: colors.primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: Colors.grey,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 分组 3：关联与提醒
                    Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 12),
                      child: Text(
                        "关联与提醒",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Card(
                      key: _relatedTodosCardKey,
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: colors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Colors.black.withValues(alpha: 0.04),
                        ),
                      ),
                      child: ListTile(
                        key: const ValueKey('fixed-schedule-related-todos'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.link_rounded,
                            color: Colors.teal,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          '关联待办',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _relatedTodoIds.isEmpty
                              ? '未关联 · 可添加复习、材料准备等待办'
                              : '已关联 ${_relatedTodoIds.length} 项 · 修改后按${_scopeLabel(_effectiveEditScope)}应用',
                          style: TextStyle(
                            fontSize: 13,
                            color: _relatedTodoIds.isEmpty
                                ? colors.onSurfaceVariant
                                : colors.primary,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_relatedTodoIds.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_relatedTodoIds.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                        onTap: _saving || _loadingContext
                            ? null
                            : _chooseRelatedTodos,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: colors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Colors.black.withValues(alpha: 0.04),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active_outlined,
                                    color: Colors.purpleAccent,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '日程提醒',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _timeTbd
                                      ? '时间确定后生效'
                                      : (_reminderMinutes.isEmpty
                                            ? '全部取消即关闭'
                                            : '已选 ${_reminderMinutes.length} 项'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  ({
                                    0,
                                    5,
                                    15,
                                    30,
                                    60,
                                    1440,
                                    ..._reminderMinutes,
                                  }.toList()..sort()).map((minutes) {
                                    final selected = _reminderMinutes.contains(
                                      minutes,
                                    );
                                    return FilterChip(
                                      label: Text(_reminderLabel(minutes)),
                                      selected: selected,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(
                                        color: selected
                                            ? colors.primary.withValues(
                                                alpha: 0.4,
                                              )
                                            : colors.outlineVariant.withValues(
                                                alpha: 0.3,
                                              ),
                                      ),
                                      showCheckmark: true,
                                      onSelected: (val) {
                                        _unfocusActiveInput();
                                        _mutateState(() {
                                          if (val) {
                                            _reminderMinutes.add(minutes);
                                          } else {
                                            _reminderMinutes.remove(minutes);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
