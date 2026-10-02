part of 'todo_chat_screen.dart';

mixin _TodoChatQueries on _TodoChatScreenStateBase {
  @override
  AiQueryToolService _createQueryToolService() => AiQueryToolService(
    loadAppData: _loadQueryAppData,
    loadHabitData: _loadQueryHabitData,
  );

  Future<List<Map<String, dynamic>>> _loadQueryAppData(String domain) async {
    final username = widget.username;
    final List<Map<String, dynamic>> rows;
    switch (domain) {
      case 'todos':
        final todos = await StorageService.getTodos(username);
        rows = [
          for (final todo in todos)
            {
              'id': todo.id,
              'title': todo.title,
              'is_completed': todo.isDone,
              'due_date': todo.dueDate?.toIso8601String(),
              'created_date': todo.createdDate,
              'is_all_day': todo.isAllDay,
              'recurrence': todo.recurrence.name,
              'recurrence_series_id': todo.recurrenceSeriesId,
              'custom_interval_days': todo.customIntervalDays,
              'recurrence_end_date': todo.recurrenceEndDate?.toIso8601String(),
              'group_id': todo.groupId,
              'remark': todo.remark,
              'is_deleted': todo.isDeleted,
            },
        ];
      case 'todo_groups':
        rows = [
          for (final item in await StorageService.getTodoGroups(username))
            item.toJson(),
        ];
      case 'courses':
        rows = [
          for (final item in widget.courses)
            {
              ...item.toJson(),
              'start_time': '${item.date}T${item.formattedStartTime}:00',
              'end_time': '${item.date}T${item.formattedEndTime}:00',
            },
        ];
      case 'fixed_schedules':
        rows = [
          for (final item in await StorageService.getFixedSchedules(username))
            {
              ...item.toJson(),
              'status': item.status.name,
              'recurrence': item.recurrence.name,
            },
        ];
      case 'plan_blocks':
        rows = [
          for (final item in await StorageService.getPlanBlocks(username))
            {
              ...item.toJson(),
              'title': item.titleSnapshot,
              'status': item.status.name,
            },
        ];
      case 'time_logs':
        rows = [
          for (final item in await StorageService.getTimeLogs(username))
            {
              ...item.toJson(),
              'duration_seconds': math.max(
                0,
                (item.endTime - item.startTime) ~/ 1000,
              ),
            },
        ];
      case 'pomodoro_records':
        rows = [
          for (final item in await PomodoroService.getRecords())
            {
              ...item.toJson(),
              'duration_seconds':
                  AiQueryToolService.durationSecondsForPomodoro(item),
            },
        ];
      case 'pomodoro_tags':
        rows = [
          for (final item in await PomodoroService.getTags()) item.toJson(),
        ];
      case 'countdowns':
        rows = [
          for (final item in await StorageService.getCountdowns(username))
            {...item.toJson(), 'due_date': item.targetDate.toIso8601String()},
        ];
      case 'teams':
        rows = [
          for (final item in widget.teams)
            {
              'id': item.uuid,
              'name': item.name,
              'member_count': item.memberCount,
              'role': item.userRole.name,
            },
        ];
      case 'conflicts':
        rows = [
          for (var index = 0; index < widget.conflicts.length; index++)
            {
              'id': index.toString(),
              'type': widget.conflicts[index].type,
              'item': widget.conflicts[index].item,
              'conflict_with': widget.conflicts[index].conflictWith,
            },
        ];
      default:
        throw const FormatException('不支持的数据域');
    }
    // Do not send device identifiers, local attachment paths, or sync payloads.
    const internalFields = {
      'device_id',
      'image_path',
      'original_text',
      'conflict_data',
      'pending_sync',
      'created_at',
      'updated_at',
      'version',
    };
    return [
      for (final row in rows)
        {
          for (final entry in row.entries)
            if (!internalFields.contains(entry.key) &&
                !(domain == 'courses' &&
                    {'startTime', 'endTime'}.contains(entry.key)))
              entry.key:
                  {
                        'start_time',
                        'end_time',
                        'target_time',
                        'created_date',
                      }.contains(entry.key) &&
                      entry.value is int
                  ? DateTime.fromMillisecondsSinceEpoch(entry.value as int)
                        .toIso8601String()
                  : entry.value,
        },
    ];
  }

  Future<List<Map<String, dynamic>>> _loadQueryHabitData(
    DateTime from,
    DateTime toExclusive,
    String? habitId,
  ) async {
    final goals = (await HabitRepository.getActiveGoals()).where(
      (goal) =>
          !goal.isDeleted &&
          !goal.isArchived &&
          (habitId == null || goal.uuid == habitId),
    );
    final rules = await HabitRepository.getRules();
    final rows = <Map<String, dynamic>>[];
    for (final goal in goals) {
      final goalRules = rules
          .where((rule) => rule.habitUuid == goal.uuid)
          .toList();
      final progress = await HabitProgressCalculator.computeRange(
        habit: goal,
        rules: goalRules,
        from: from,
        to: DateTime(toExclusive.year, toExclusive.month, toExclusive.day - 1),
        periodLevel: true,
      );
      final planned = progress
          .where((item) => item.progress.isPlanned && !item.progress.isSkipped)
          .toList();
      final finished = planned
          .where((item) => item.progress.isFinished)
          .toList();
      final met = planned.where((item) => item.progress.goalMet).length;
      rows.add({
        'id': goal.uuid,
        'name': goal.name,
        'unit': goalRules.lastOrNull?.unit,
        'source_type': goal.sourceType.name,
        'rules': [for (final rule in goalRules) rule.toJson()],
        'progress': {
          'planned_periods': planned.length,
          'met_periods': met,
          'finished_periods': finished.length,
          'finished_met_periods': finished
              .where((item) => item.progress.goalMet)
              .length,
          'in_progress_periods': planned
              .where(
                (item) => !item.progress.isFinished && !item.progress.goalMet,
              )
              .length,
          'skipped_periods': progress
              .where((item) => item.progress.isSkipped)
              .length,
          'record_count': progress.fold<int>(
            0,
            (sum, item) => sum + item.progress.recordCount,
          ),
        },
      });
    }
    return rows;
  }
}
