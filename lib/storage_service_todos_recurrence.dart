part of 'storage_service.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

class _TodoRecurrenceOccurrenceIndex {
  _TodoRecurrenceOccurrenceIndex(Iterable<TodoItem> todos, this._dayKeyFor) {
    for (final todo in todos) {
      add(todo);
    }
  }

  final String Function(int) _dayKeyFor;
  final Map<String, List<TodoItem>> _bySeries = {};
  final Map<String, Map<String, List<TodoItem>>> _bySeriesDay = {};

  void add(TodoItem todo) {
    final seriesId = todo.recurrenceSeriesId;
    if (seriesId == null || seriesId.isEmpty) return;

    final dayKey = _dayKeyFor(todo.createdDate ?? todo.createdAt);
    _bySeries.putIfAbsent(seriesId, () => []).add(todo);
    _bySeriesDay
        .putIfAbsent(seriesId, () => {})
        .putIfAbsent(dayKey, () => [])
        .add(todo);
  }

  List<TodoItem> forSeries(String seriesId) =>
      _bySeries[seriesId] ?? const <TodoItem>[];

  List<TodoItem> forSeriesDay(String seriesId, String dayKey) =>
      _bySeriesDay[seriesId]?[dayKey] ?? const <TodoItem>[];
}

mixin _StorageTodoRecurrence on _StorageServiceBase {
  Future<List<TodoItem>> _handleRecurrenceLogic(
    String username,
    List<TodoItem> todos,
  ) async {
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month}-${today.day}';

    if (_lastRecurrenceCheckDate != todayKey) {
      _lastRecurrenceCheckDate = todayKey;
      _recurrenceCheckCache.clear();
    }

    final cacheKey = 'recurrence_instances_v4_$username';
    if (_recurrenceCheckCache.containsKey(cacheKey) || _isCheckingRecurrence) {
      return todos;
    }

    _isCheckingRecurrence = true;

    try {
      final recurrenceDb = await DatabaseHelper.instance.databaseForUser(
        username,
      );
      final permanentlyDeletedIds = (await recurrenceDb.query(
        'op_logs',
        columns: const ['target_uuid'],
        where: "target_table = 'todos' AND op_type = 'DELETE'",
      )).map((row) => row['target_uuid']?.toString() ?? '').toSet();
      permanentlyDeletedIds.remove('');
      final baselines = {
        for (final todo in todos) todo.id: todo.detachedCopy(),
      };
      bool needSave = false;
      var maintenanceSaved = true;
      if (_deduplicatePersistedRecurrenceOccurrences(todos)) {
        needSave = true;
      }
      final occurrenceIndex = todos.length > 50
          ? _TodoRecurrenceOccurrenceIndex(todos, _recurrenceLocalDayKey)
          : null;
      final List<TodoItem> generatedOccurrences = [];
      final Set<String> generatedRecurrenceConflictKeys = {};
      final processedSeriesIds = <String>{};
      // Generated occurrences stay in their own buffer until this pass ends.
      for (final todo in todos) {
        if (todo.isDeleted || todo.recurrence == RecurrenceType.none) continue;

        final hasSeriesId =
            todo.recurrenceSeriesId != null &&
            todo.recurrenceSeriesId!.isNotEmpty;
        final seriesId = hasSeriesId ? todo.recurrenceSeriesId! : todo.id;
        todo.recurrenceSeriesId = seriesId;
        if (!hasSeriesId) occurrenceIndex?.add(todo);
        if (!processedSeriesIds.add(seriesId)) continue;

        final DateTime baseLocal = _getRecurrenceBaseDate(todo);
        final DateTime baseDay = DateTime(
          baseLocal.year,
          baseLocal.month,
          baseLocal.day,
        );
        final DateTime todayDay = DateTime(today.year, today.month, today.day);
        final rollOffsets = _recurrenceRollOffsets(todo, baseDay, todayDay);
        final recurrence = todo.recurrence;
        final recurrenceEndDay = todo.recurrenceEndDate == null
            ? null
            : DateTime(
                todo.recurrenceEndDate!.year,
                todo.recurrenceEndDate!.month,
                todo.recurrenceEndDate!.day,
              );
        final keepSeriesActive =
            recurrenceEndDay == null || !todayDay.isAfter(recurrenceEndDay);
        if (recurrenceEndDay != null) {
          // 结束日期可能只修改了当前锚点，或来自另一台设备的同步；不能
          // 依赖编辑页一定把所有未来实例一起带回来。存储层每次处理规则
          // 时都清理结束日期之后的旧实例，避免它们继续留在系列中，或在
          // 旧锚点仍存活时被再次生成。
          final seriesOccurrences =
              occurrenceIndex?.forSeries(seriesId) ??
              todos.followedBy(generatedOccurrences);
          if (_pruneRecurrenceOccurrencesAfterEndDate(
            seriesOccurrences.where((occurrence) => occurrence.id != todo.id),
            seriesId: seriesId,
            recurrenceEndDate: recurrenceEndDay,
          )) {
            needSave = true;
          }
        }
        final seriesChain = <TodoItem>[todo];
        var activeOccurrence = todo;
        var todoChanged = !hasSeriesId;

        for (var i = 0; i < rollOffsets.length; i++) {
          final result = _getOrCreateRecurrenceOccurrence(
            source: todo,
            rollByDays: rollOffsets[i],
            seriesId: seriesId,
            todos: todos,
            generatedOccurrences: generatedOccurrences,
            occurrenceIndex: occurrenceIndex,
            permanentlyDeletedTodoIds: permanentlyDeletedIds,
          );
          final occurrence = result.occurrence;
          final targetRecurrence =
              i == rollOffsets.length - 1 && keepSeriesActive
              ? recurrence
              : RecurrenceType.none;
          if (occurrence.recurrence != targetRecurrence) {
            occurrence.recurrence = targetRecurrence;
            if (!result.isNew) occurrence.markRecurrenceMaintenanceChanged();
            needSave = true;
          }
          if (result.didChange) needSave = true;
          seriesChain.add(occurrence);
          activeOccurrence = occurrence;
        }

        final repairedPastOccurrences = _repairMissingPastRecurrenceOccurrences(
          ruleSource: todo,
          copySource: activeOccurrence,
          seriesId: seriesId,
          throughStartMs:
              activeOccurrence.createdDate ?? activeOccurrence.createdAt,
          todos: todos,
          generatedOccurrences: generatedOccurrences,
          occurrenceIndex: occurrenceIndex,
          permanentlyDeletedTodoIds: permanentlyDeletedIds,
        );
        if (repairedPastOccurrences.isNotEmpty) {
          seriesChain.addAll(repairedPastOccurrences);
          needSave = true;
        }

        if (rollOffsets.isNotEmpty) {
          // 原实例保留自己的完成状态，当前日期对应实例接管循环锚点。
          todo.recurrence = RecurrenceType.none;
          todoChanged = true;
        }

        // 如果结束日期被改到了当前锚点之前，rollOffsets 为空，原有逻辑
        // 会错误地继续保留 recurrence，导致后续每次读取都把它当作活动规则。
        if (!keepSeriesActive && todo.recurrence != RecurrenceType.none) {
          todo.recurrence = RecurrenceType.none;
          todoChanged = true;
        }

        if (todoChanged) {
          todo.markRecurrenceMaintenanceChanged();
          needSave = true;
        }

        if (activeOccurrence.recurrence != RecurrenceType.none) {
          final activeBase = _getRecurrenceBaseDate(activeOccurrence);
          final futureOffsets = _futureRecurrenceRollOffsets(
            activeOccurrence,
            activeBase,
          );
          for (final offset in futureOffsets) {
            final result = _getOrCreateRecurrenceOccurrence(
              source: activeOccurrence,
              rollByDays: offset,
              seriesId: seriesId,
              todos: todos,
              generatedOccurrences: generatedOccurrences,
              occurrenceIndex: occurrenceIndex,
              permanentlyDeletedTodoIds: permanentlyDeletedIds,
            );
            final occurrence = result.occurrence;
            if (occurrence.recurrence != RecurrenceType.none) {
              occurrence.recurrence = RecurrenceType.none;
              if (!result.isNew) occurrence.markRecurrenceMaintenanceChanged();
              needSave = true;
            }
            if (result.didChange) needSave = true;
            seriesChain.add(occurrence);
          }
        }

        final uniqueSeriesChain = <String, TodoItem>{
          for (final occurrence in seriesChain) occurrence.id: occurrence,
        }.values.toList();
        _addRecurrenceOverlapKeys(
          uniqueSeriesChain,
          generatedRecurrenceConflictKeys,
        );
      }

      if (_pruneRecurrenceOccurrencesAfterEndDates([
        ...todos,
        ...generatedOccurrences,
      ]).isNotEmpty) {
        needSave = true;
      }
      if (needSave) {
        todos.addAll(generatedOccurrences);
        if (generatedRecurrenceConflictKeys.isNotEmpty) {
          final ignoredKeys = await _getIgnoredScheduleConflictKeys(username)
            ..addAll(generatedRecurrenceConflictKeys);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(
            _scopedKey(keyIgnoredScheduleConflicts, username),
            ignoredKeys.toList()..sort(),
          );
        }
        debugPrint("🚀 [Recurrence] 发现重复任务需要滚动，正在保存...");
        maintenanceSaved = await _saveRecurrenceMaintenance(
          username,
          todos,
          baselines,
        );
      }
      if (maintenanceSaved) _recurrenceCheckCache[cacheKey] = true;
      _isCheckingRecurrence = false;
      return todos;
    } catch (e) {
      debugPrint("❌ [Recurrence] 逻辑异常: $e");
      _isCheckingRecurrence = false;
      return todos;
    }
  }

  DateTime _getRecurrenceBaseDate(TodoItem todo) {
    if (todo.createdDate != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate!,
        isUtc: true,
      ).toLocal();
    }
    return todo.dueDate ??
        DateTime.fromMillisecondsSinceEpoch(
          todo.createdAt,
          isUtc: true,
        ).toLocal();
  }

  List<int> _recurrenceRollOffsets(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  ) {
    var targetDay = todayDay;
    if (todo.recurrenceEndDate != null) {
      final end = todo.recurrenceEndDate!;
      final endDay = DateTime(end.year, end.month, end.day);
      if (endDay.isBefore(targetDay)) targetDay = endDay;
    }
    if (!targetDay.isAfter(baseDay)) return const [];

    final offsets = <int>[];
    const maxBackfilledOccurrences = 90;
    final diffDays = CalendarDateMath.daysBetween(baseDay, targetDay);
    switch (todo.recurrence) {
      case RecurrenceType.daily:
        final firstDay = diffDays > maxBackfilledOccurrences
            ? diffDays - maxBackfilledOccurrences + 1
            : 1;
        for (var day = firstDay; day <= diffDays; day++) {
          offsets.add(day);
        }
      case RecurrenceType.customDays:
        final interval = todo.customIntervalDays ?? 0;
        if (interval > 0) {
          final occurrenceCount = diffDays ~/ interval;
          final firstOccurrence = occurrenceCount > maxBackfilledOccurrences
              ? occurrenceCount - maxBackfilledOccurrences + 1
              : 1;
          for (
            var occurrence = firstOccurrence;
            occurrence <= occurrenceCount;
            occurrence++
          ) {
            offsets.add(occurrence * interval);
          }
        }
      case RecurrenceType.weekdays:
        // A 126-day window contains exactly 90 weekdays. Start at the
        // earliest offset in that window, avoiding work for older dates that
        // would be discarded by the backfill cap below.
        final firstDay = diffDays > 126 ? diffDays - 125 : 1;
        var weekday = DateTime(
          baseDay.year,
          baseDay.month,
          baseDay.day + firstDay,
        ).weekday;
        for (var day = firstDay; day <= diffDays; day++) {
          if (weekday != DateTime.saturday && weekday != DateTime.sunday) {
            offsets.add(day);
          }
          weekday = weekday == DateTime.sunday ? DateTime.monday : weekday + 1;
        }
      case RecurrenceType.weekly:
        final occurrenceCount = diffDays ~/ 7;
        final firstOccurrence = occurrenceCount > maxBackfilledOccurrences
            ? occurrenceCount - maxBackfilledOccurrences + 1
            : 1;
        for (
          var occurrence = firstOccurrence;
          occurrence <= occurrenceCount;
          occurrence++
        ) {
          offsets.add(occurrence * 7);
        }
      case RecurrenceType.monthly:
      case RecurrenceType.yearly:
        var candidate = _nextRecurrenceDate(baseDay, todo);
        while (candidate != null && !candidate.isAfter(targetDay)) {
          offsets.add(CalendarDateMath.daysBetween(baseDay, candidate));
          candidate = _nextRecurrenceDate(candidate, todo);
        }
      case RecurrenceType.none:
        break;
    }

    // 防止长期未启动后一次性生成过量记录，同时优先保留最近周期。
    if (offsets.length <= maxBackfilledOccurrences) return offsets;
    return offsets.sublist(offsets.length - maxBackfilledOccurrences);
  }

  List<int> recurrenceRollOffsetsForTest(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  ) => _recurrenceRollOffsets(todo, baseDay, todayDay);
  List<TodoItem> futureRecurrenceOccurrencesForTest(
    TodoItem source,
    List<TodoItem> existing,
  ) {
    final generated = <TodoItem>[];
    final seriesId = source.recurrenceSeriesId ?? source.id;
    source.recurrenceSeriesId = seriesId;
    final base = _getRecurrenceBaseDate(source);
    for (final offset in _futureRecurrenceRollOffsets(source, base)) {
      final result = _getOrCreateRecurrenceOccurrence(
        source: source,
        rollByDays: offset,
        seriesId: seriesId,
        todos: existing,
        generatedOccurrences: generated,
      );
      result.occurrence.recurrence = RecurrenceType.none;
    }
    return generated;
  }

  List<TodoItem> repairMissingPastRecurrenceOccurrencesForTest(
    TodoItem active,
    List<TodoItem> existing,
  ) {
    final generated = <TodoItem>[];
    final seriesId = active.recurrenceSeriesId ?? active.id;
    active.recurrenceSeriesId = seriesId;
    return _repairMissingPastRecurrenceOccurrences(
      ruleSource: active,
      copySource: active,
      seriesId: seriesId,
      throughStartMs: active.createdDate ?? active.createdAt,
      todos: existing,
      generatedOccurrences: generated,
    );
  }

  bool pruneRecurrenceOccurrencesAfterEndDateForTest(
    List<TodoItem> todos, {
    required String seriesId,
    required DateTime recurrenceEndDate,
  }) => _pruneRecurrenceOccurrencesAfterEndDate(
    todos,
    seriesId: seriesId,
    recurrenceEndDate: recurrenceEndDate,
  );

  Set<String> pruneRecurrenceOccurrencesAfterEndDatesForTest(
    List<TodoItem> todos,
  ) => _pruneRecurrenceOccurrencesAfterEndDates(todos);

  String recurrenceOccurrenceIdForTest(String seriesId, int startMs) =>
      _recurrenceOccurrenceId(seriesId, startMs);
  bool deduplicatePersistedRecurrenceOccurrencesForTest(List<TodoItem> todos) =>
      _deduplicatePersistedRecurrenceOccurrences(todos);
  Future<int> mergeRecurrenceSeries(
    String username, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) async {
    final todos = await getTodos(username, includeDeleted: true);
    final changedIds = _mergeRecurrenceSeries(
      todos,
      targetSeriesId: targetSeriesId,
      seriesIds: seriesIds,
    );
    if (changedIds.isEmpty) return 0;

    final changedItems = todos
        .where((todo) => changedIds.contains(todo.id))
        .toList();
    await saveTodos(
      username,
      changedItems,
      sync: true,
      recomputeScheduleConflicts: false,
    );
    await _refreshTodoScheduleConflicts(username);
    triggerRefresh(const {DataRefreshDomain.todos});
    return changedItems.length;
  }

  Set<String> mergeRecurrenceSeriesForTest(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) => _mergeRecurrenceSeries(
    todos,
    targetSeriesId: targetSeriesId,
    seriesIds: seriesIds,
  );
  Set<String> _mergeRecurrenceSeries(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) {
    final selectedSeriesIds = <String>{...seriesIds, targetSeriesId}
      ..removeWhere((seriesId) => seriesId.trim().isEmpty);
    final participating = todos
        .where(
          (todo) =>
              todo.recurrenceSeriesId != null &&
              selectedSeriesIds.contains(todo.recurrenceSeriesId),
        )
        .toList();
    final activeSeriesIds = participating
        .where((todo) => !todo.isDeleted)
        .map((todo) => todo.recurrenceSeriesId)
        .whereType<String>()
        .toSet();
    if (activeSeriesIds.length < 2 ||
        !activeSeriesIds.contains(targetSeriesId)) {
      return <String>{};
    }

    TodoItem? canonicalActive;
    final activeRules =
        participating
            .where(
              (todo) =>
                  !todo.isDeleted && todo.recurrence != RecurrenceType.none,
            )
            .toList()
          ..sort((a, b) {
            final startCompare = (b.createdDate ?? b.createdAt).compareTo(
              a.createdDate ?? a.createdAt,
            );
            if (startCompare != 0) return startCompare;
            return b.version.compareTo(a.version);
          });
    for (final todo in activeRules) {
      if (todo.recurrenceSeriesId == targetSeriesId) {
        canonicalActive = todo;
        break;
      }
    }
    canonicalActive ??= activeRules.isEmpty ? null : activeRules.first;

    final versionsBefore = {
      for (final todo in participating) todo.id: todo.version,
    };
    final fieldChangedIds = <String>{};

    // 系列被拆分并多次去重后，完成状态可能只保留在源系列中已经删除的
    // 重复实例上。合并时按发生日期取完成状态并集，再写回该日仍可见的
    // 实例；目标系列中早已删除的旧状态不参与，避免覆盖用户后续的取消完成。
    final completedDays = participating
        .where(
          (todo) =>
              todo.isDone &&
              (!todo.isDeleted || todo.recurrenceSeriesId != targetSeriesId),
        )
        .map(
          (todo) => _recurrenceLocalDayKey(todo.createdDate ?? todo.createdAt),
        )
        .toSet();
    for (final todo in participating) {
      if (todo.isDeleted || todo.isDone) continue;
      final dayKey = _recurrenceLocalDayKey(todo.createdDate ?? todo.createdAt);
      if (!completedDays.contains(dayKey)) continue;
      todo.isDone = true;
      fieldChangedIds.add(todo.id);
    }

    for (final todo in participating) {
      if (todo.recurrenceSeriesId != targetSeriesId) {
        todo.recurrenceSeriesId = targetSeriesId;
        fieldChangedIds.add(todo.id);
      }
      if (todo.recurrence != RecurrenceType.none &&
          todo.id != canonicalActive?.id) {
        todo.recurrence = RecurrenceType.none;
        fieldChangedIds.add(todo.id);
      }
    }

    _deduplicatePersistedRecurrenceOccurrences(participating);
    final changedIds = <String>{};
    for (final todo in participating) {
      if (todo.version != versionsBefore[todo.id]) {
        changedIds.add(todo.id);
      }
    }
    for (final todo in participating) {
      if (!fieldChangedIds.contains(todo.id)) continue;
      changedIds.add(todo.id);
    }
    // This entry point is an explicit user merge, unlike automatic repair.
    for (final todo in participating) {
      if (changedIds.contains(todo.id)) todo.markAsChanged();
    }
    return changedIds;
  }

  List<int> _futureRecurrenceRollOffsets(TodoItem todo, DateTime baseLocal) {
    final baseDay = DateTime(baseLocal.year, baseLocal.month, baseLocal.day);
    final recurrenceEnd = todo.recurrenceEndDate;
    if (recurrenceEnd != null) {
      final endDay = DateTime(
        recurrenceEnd.year,
        recurrenceEnd.month,
        recurrenceEnd.day,
      );
      return _recurrenceRollOffsets(todo, baseDay, endDay);
    }

    final offsets = <int>[];
    var cursor = baseLocal;
    for (var i = 0; i < 2; i++) {
      final next = _nextRecurrenceDate(cursor, todo);
      if (next == null || !next.isAfter(cursor)) break;
      offsets.add(CalendarDateMath.daysBetween(baseDay, next));
      cursor = next;
    }
    return offsets;
  }

  DateTime? _nextRecurrenceDate(DateTime current, TodoItem todo) {
    return TodoRecurrenceDateService.nextDate(current, todo);
  }

  ({TodoItem occurrence, bool isNew, bool didChange})
  _getOrCreateRecurrenceOccurrence({
    required TodoItem source,
    required int rollByDays,
    required String seriesId,
    required List<TodoItem> todos,
    required List<TodoItem> generatedOccurrences,
    _TodoRecurrenceOccurrenceIndex? occurrenceIndex,
    Set<String> permanentlyDeletedTodoIds = const {},
  }) {
    final candidate = _copyForNextRecurrence(source);
    candidate.recurrenceSeriesId = seriesId;
    _rollRecurrenceDateByDays(candidate, rollByDays);
    final candidateStart = candidate.createdDate ?? candidate.createdAt;
    final candidateDayKey = _recurrenceLocalDayKey(candidateStart);
    candidate.id = _recurrenceOccurrenceId(seriesId, candidateStart);

    final List<TodoItem> matches;
    if (occurrenceIndex != null) {
      matches = occurrenceIndex.forSeriesDay(seriesId, candidateDayKey);
    } else {
      matches = <TodoItem>[];
      for (final existing in todos.followedBy(generatedOccurrences)) {
        if (existing.recurrenceSeriesId != seriesId ||
            _recurrenceLocalDayKey(
                  existing.createdDate ?? existing.createdAt,
                ) !=
                candidateDayKey) {
          continue;
        }
        matches.add(existing);
      }
    }

    final liveMatches = matches.where((todo) => !todo.isDeleted).toList();
    if (liveMatches.isNotEmpty) {
      liveMatches.sort(_compareRecurrenceOccurrenceIdentity);
      return (occurrence: liveMatches.first, isNew: false, didChange: false);
    }

    final deletedDeterministic = matches
        .where((todo) => todo.id == candidate.id)
        .firstOrNull;
    if (deletedDeterministic != null) {
      if (!_recurrenceDedupeTombstoneIds.contains(deletedDeterministic.id)) {
        // A durable user deletion is a period-level tombstone. Do not turn it
        // back into an active item merely because recurrence repair visits the
        // same deterministic date again.
        return (
          occurrence: deletedDeterministic,
          isNew: false,
          didChange: false,
        );
      }
      _copyRecurrenceOccurrenceData(candidate, deletedDeterministic);
      deletedDeterministic.isDeleted = false;
      deletedDeterministic.markRecurrenceMaintenanceChanged();
      _recurrenceDedupeTombstoneIds.remove(deletedDeterministic.id);
      return (occurrence: deletedDeterministic, isNew: false, didChange: true);
    }

    if (permanentlyDeletedTodoIds.contains(candidate.id)) {
      // A hard-deleted recurring period has no todo row left to act as its
      // durable tombstone. Its DELETE oplog is the persisted suppression
      // marker, so recurrence maintenance must not recreate that UUID.
      return (occurrence: candidate, isNew: false, didChange: false);
    }

    generatedOccurrences.add(candidate);
    occurrenceIndex?.add(candidate);
    return (occurrence: candidate, isNew: true, didChange: true);
  }

  String _recurrenceLocalDayKey(int startMs) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      startMs,
      isUtc: true,
    ).toLocal();
    return AppTimeFormats.date(start);
  }

  String _recurrenceOccurrenceId(String seriesId, int startMs) {
    final dayKey = _recurrenceLocalDayKey(startMs);
    return const Uuid().v5(
      _recurrenceOccurrenceNamespace,
      'countdown-todo/recurrence-occurrence/v1/$seriesId/$dayKey',
    );
  }

  List<TodoItem> _repairMissingPastRecurrenceOccurrences({
    required TodoItem ruleSource,
    required TodoItem copySource,
    required String seriesId,
    required int throughStartMs,
    required List<TodoItem> todos,
    required List<TodoItem> generatedOccurrences,
    _TodoRecurrenceOccurrenceIndex? occurrenceIndex,
    Set<String> permanentlyDeletedTodoIds = const {},
  }) {
    final knownByDay = <String, DateTime>{};
    final occurrences =
        occurrenceIndex?.forSeries(seriesId) ??
        todos.followedBy(generatedOccurrences);
    for (final occurrence in occurrences) {
      if (occurrence.isDeleted || occurrence.recurrenceSeriesId != seriesId) {
        continue;
      }
      final startMs = occurrence.createdDate ?? occurrence.createdAt;
      if (startMs > throughStartMs) continue;
      final start = DateTime.fromMillisecondsSinceEpoch(
        startMs,
        isUtc: true,
      ).toLocal();
      final day = DateTime(start.year, start.month, start.day);
      knownByDay['${day.year}-${day.month}-${day.day}'] = day;
    }

    final knownDays = knownByDay.values.toList()..sort();
    if (knownDays.length < 2) return const [];

    final copyBase = _getRecurrenceBaseDate(copySource);
    final copyBaseDay = DateTime(copyBase.year, copyBase.month, copyBase.day);
    final repaired = <TodoItem>[];
    for (var index = 0; index < knownDays.length - 1; index++) {
      final previousDay = knownDays[index];
      final nextKnownDay = knownDays[index + 1];
      final candidateOffsets = _recurrenceRollOffsets(
        ruleSource,
        previousDay,
        nextKnownDay,
      );
      for (final candidateOffset in candidateOffsets) {
        final candidateDay = DateTime(
          previousDay.year,
          previousDay.month,
          previousDay.day + candidateOffset,
        );
        if (!candidateDay.isBefore(nextKnownDay)) continue;

        final rollByDays = CalendarDateMath.daysBetween(
          copyBaseDay,
          candidateDay,
        );
        final result = _getOrCreateRecurrenceOccurrence(
          source: copySource,
          rollByDays: rollByDays,
          seriesId: seriesId,
          todos: todos,
          generatedOccurrences: generatedOccurrences,
          occurrenceIndex: occurrenceIndex,
          permanentlyDeletedTodoIds: permanentlyDeletedTodoIds,
        );
        if (!result.didChange) continue;
        result.occurrence.recurrence = RecurrenceType.none;
        repaired.add(result.occurrence);
      }
    }
    return repaired;
  }

  bool _deduplicatePersistedRecurrenceOccurrences(
    List<TodoItem> todos, {
    Set<String>? changedIds,
  }) {
    final occurrencesBySeriesDay = <String, List<TodoItem>>{};
    for (final todo in todos) {
      final seriesId = todo.recurrenceSeriesId;
      if (seriesId == null || seriesId.isEmpty) continue;
      final startMs = todo.createdDate ?? todo.createdAt;
      final key = '$seriesId|${_recurrenceLocalDayKey(startMs)}';
      occurrencesBySeriesDay.putIfAbsent(key, () => []).add(todo);
    }

    var changed = false;
    for (final occurrences in occurrencesBySeriesDay.values) {
      if (occurrences.length <= 1) continue;
      final liveOccurrences = occurrences
          .where((todo) => !todo.isDeleted)
          .toList();
      if (liveOccurrences.isEmpty) continue;

      // Identity must not depend on mutable LWW fields. Every device will
      // eventually select the same oldest physical occurrence, even if it
      // initially saw only a subset of the duplicates.
      occurrences.sort(_compareRecurrenceOccurrenceIdentity);
      final canonical = occurrences.first;
      // 复用普通待办的严格 LWW 顺序：updated_at 优先，只有时间相同才比较
      // version。旧设备可能因为本地重复实例修复而拥有更高 version，但这
      // 不代表它的完成状态比服务器上较新的实例更可信。
      liveOccurrences.sort(_compareRecurrenceOccurrenceLwwDescending);
      final dataWinner = liveOccurrences.first;
      final completionWinner = dataWinner;
      final activeOccurrences =
          liveOccurrences
              .where((todo) => todo.recurrence != RecurrenceType.none)
              .toList()
            ..sort(_compareRecurrenceOccurrenceLwwDescending);
      final mergedRecurrence = activeOccurrences.isEmpty
          ? RecurrenceType.none
          : activeOccurrences.first.recurrence;

      var canonicalChanged = false;
      if (!identical(canonical, dataWinner)) {
        canonicalChanged =
            _copyRecurrenceOccurrenceData(dataWinner, canonical) ||
            canonicalChanged;
      }
      if (canonical.isDeleted) {
        canonical.isDeleted = false;
        canonicalChanged = true;
      }
      if (canonical.isDone != completionWinner.isDone) {
        canonical.isDone = completionWinner.isDone;
        canonical.completedAt = completionWinner.completedAt;
        canonicalChanged = true;
      }
      if (canonical.recurrence != mergedRecurrence) {
        canonical.recurrence = mergedRecurrence;
        canonicalChanged = true;
      }
      if (canonicalChanged) {
        // 这是结构性去重，不是用户的新编辑。沿用获胜实例的 LWW 元数据，
        // 避免把旧的未完成副本通过 markAsChanged() 伪装成当前新写入。
        canonical.version = dataWinner.version;
        canonical.updatedAt = dataWinner.updatedAt;
        _recurrenceDedupeTombstoneIds.remove(canonical.id);
        changedIds?.add(canonical.id);
        changed = true;
      }

      for (final duplicate in occurrences) {
        if (identical(duplicate, canonical)) continue;
        if (duplicate.isDeleted &&
            duplicate.recurrence == RecurrenceType.none) {
          continue;
        }
        duplicate.isDeleted = true;
        duplicate.recurrence = RecurrenceType.none;
        duplicate.markRecurrenceMaintenanceChanged();
        _recurrenceDedupeTombstoneIds.add(duplicate.id);
        changedIds?.add(duplicate.id);
        changed = true;
      }
    }
    return changed;
  }

  bool _pruneRecurrenceOccurrencesAfterEndDate(
    Iterable<TodoItem> todos, {
    required String seriesId,
    required DateTime recurrenceEndDate,
    Set<String>? changedIds,
  }) {
    final endDay = DateTime(
      recurrenceEndDate.year,
      recurrenceEndDate.month,
      recurrenceEndDate.day,
    );
    var changed = false;
    for (final occurrence in todos) {
      if (occurrence.isDeleted || occurrence.recurrenceSeriesId != seriesId) {
        continue;
      }
      final startMs = occurrence.createdDate ?? occurrence.createdAt;
      final start = DateTime.fromMillisecondsSinceEpoch(
        startMs,
        isUtc: true,
      ).toLocal();
      final startDay = DateTime(start.year, start.month, start.day);
      if (!startDay.isAfter(endDay)) continue;

      occurrence.isDeleted = true;
      occurrence.recurrence = RecurrenceType.none;
      occurrence.markRecurrenceMaintenanceChanged();
      changedIds?.add(occurrence.id);
      changed = true;
    }
    return changed;
  }

  Map<String, TodoItem> _recurrenceBoundaryRulesBySeries(
    Iterable<TodoItem> todos,
  ) {
    final activeRulesBySeries = <String, TodoItem>{};
    final endedRulesBySeries = <String, TodoItem>{};
    for (final todo in todos) {
      if (todo.isDeleted) continue;
      final seriesId =
          todo.recurrenceSeriesId?.trim() ??
          (todo.recurrence != RecurrenceType.none ? todo.id : null);
      if (seriesId == null || seriesId.isEmpty) continue;

      final rules = todo.recurrence != RecurrenceType.none
          ? activeRulesBySeries
          : endedRulesBySeries;
      if (todo.recurrence == RecurrenceType.none &&
          todo.recurrenceEndDate == null) {
        continue;
      }
      final current = rules[seriesId];
      if (current == null ||
          _compareRecurrenceOccurrenceLwwDescending(todo, current) < 0) {
        rules[seriesId] = todo;
      }
    }
    // Rollover clears recurrence after the final day, but the saved end date
    // still bounds the series. An active rule (including an unlimited one)
    // takes precedence so an explicit extension can resume the series.
    return {...endedRulesBySeries, ...activeRulesBySeries};
  }

  Set<String> _pruneRecurrenceOccurrencesAfterEndDates(List<TodoItem> todos) {
    final rulesBySeries = _recurrenceBoundaryRulesBySeries(todos);
    final changedIds = <String>{};
    final now = DateTime.now();
    final todayDay = DateTime(now.year, now.month, now.day);
    final rulesToPrune = rulesBySeries.entries
        .where((entry) => entry.value.recurrenceEndDate != null)
        .toList(growable: false);
    Map<String, List<TodoItem>>? todosBySeries;
    if (rulesToPrune.length > 1) {
      final seriesIds = {for (final entry in rulesToPrune) entry.key};
      todosBySeries = {};
      for (final todo in todos) {
        final seriesId = todo.recurrenceSeriesId;
        if (seriesId == null || !seriesIds.contains(seriesId)) continue;
        todosBySeries.putIfAbsent(seriesId, () => []).add(todo);
      }
    }

    for (final entry in rulesToPrune) {
      final rule = entry.value;
      final recurrenceEndDate = rule.recurrenceEndDate;
      if (recurrenceEndDate == null) continue;
      final endDay = DateTime(
        recurrenceEndDate.year,
        recurrenceEndDate.month,
        recurrenceEndDate.day,
      );

      if (todayDay.isAfter(endDay) && rule.recurrence != RecurrenceType.none) {
        rule.recurrence = RecurrenceType.none;
        rule.markRecurrenceMaintenanceChanged();
        changedIds.add(rule.id);
      }

      final seriesTodos = todosBySeries == null
          ? todos
          : todosBySeries[entry.key] ?? const <TodoItem>[];
      _pruneRecurrenceOccurrencesAfterEndDate(
        seriesTodos.where((todo) => todo.id != rule.id),
        seriesId: entry.key,
        recurrenceEndDate: endDay,
        changedIds: changedIds,
      );
    }
    return changedIds;
  }

  int _compareRecurrenceOccurrenceLwwDescending(TodoItem a, TodoItem b) {
    final lwwOrder = TodoLwwService.compare(
      incomingUpdatedAt: a.updatedAt,
      incomingVersion: a.version,
      currentUpdatedAt: b.updatedAt,
      currentVersion: b.version,
    );
    if (lwwOrder != 0) return -lwwOrder;
    return a.id.compareTo(b.id);
  }

  int _compareRecurrenceOccurrenceIdentity(TodoItem a, TodoItem b) {
    final createdAtComparison = a.createdAt.compareTo(b.createdAt);
    if (createdAtComparison != 0) return createdAtComparison;
    return a.id.compareTo(b.id);
  }

  bool _copyRecurrenceOccurrenceData(TodoItem source, TodoItem target) {
    var changed = false;

    void assign<T>(T current, T next, void Function(T) setter) {
      if (current == next) return;
      setter(next);
      changed = true;
    }

    assign(target.title, source.title, (value) => target.title = value);
    assign(
      target.completedAt,
      source.completedAt,
      (value) => target.completedAt = value,
    );
    assign(
      target.createdDate,
      source.createdDate,
      (value) => target.createdDate = value,
    );
    assign(target.dueDate, source.dueDate, (value) => target.dueDate = value);
    assign(
      target.recurrenceSeriesId,
      source.recurrenceSeriesId,
      (value) => target.recurrenceSeriesId = value,
    );
    assign(
      target.customIntervalDays,
      source.customIntervalDays,
      (value) => target.customIntervalDays = value,
    );
    assign(
      target.recurrenceEndDate,
      source.recurrenceEndDate,
      (value) => target.recurrenceEndDate = value,
    );
    assign(target.remark, source.remark, (value) => target.remark = value);
    assign(
      target.imagePath,
      source.imagePath,
      (value) => target.imagePath = value,
    );
    assign(
      target.originalText,
      source.originalText,
      (value) => target.originalText = value,
    );
    assign(target.groupId, source.groupId, (value) => target.groupId = value);
    assign(
      target.reminderMinutes,
      source.reminderMinutes,
      (value) => target.reminderMinutes = value,
    );
    assign(
      target.teamUuid,
      source.teamUuid,
      (value) => target.teamUuid = value,
    );
    assign(
      target.creatorId,
      source.creatorId,
      (value) => target.creatorId = value,
    );
    assign(
      target.creatorName,
      source.creatorName,
      (value) => target.creatorName = value,
    );
    assign(
      target.teamName,
      source.teamName,
      (value) => target.teamName = value,
    );
    assign(
      target.collabType,
      source.collabType,
      (value) => target.collabType = value,
    );
    assign(
      target.isAllDay,
      source.isAllDay,
      (value) => target.isAllDay = value,
    );
    assign(
      target.categoryId,
      source.categoryId,
      (value) => target.categoryId = value,
    );
    return changed;
  }

  void _addRecurrenceOverlapKeys(
    List<TodoItem> seriesChain,
    Set<String> conflictKeys,
  ) {
    if (seriesChain.length <= 16) {
      for (var i = 0; i < seriesChain.length; i++) {
        for (var j = i + 1; j < seriesChain.length; j++) {
          final conflictKey = _overlappingRecurrencePairKey(
            seriesChain[i],
            seriesChain[j],
          );
          if (conflictKey != null) conflictKeys.add(conflictKey);
        }
      }
      return;
    }

    final intervals = seriesChain.where((todo) => todo.dueDate != null).toList()
      ..sort((a, b) {
        final startCompare = (a.createdDate ?? a.createdAt).compareTo(
          b.createdDate ?? b.createdAt,
        );
        return startCompare != 0 ? startCompare : a.id.compareTo(b.id);
      });
    final active = <TodoItem>[];
    for (final next in intervals) {
      final nextStart = next.createdDate ?? next.createdAt;
      final nextEnd = next.dueDate!.millisecondsSinceEpoch;
      active.removeWhere(
        (previous) => previous.dueDate!.millisecondsSinceEpoch <= nextStart,
      );

      // Active intervals stay start-sorted. Later starts cannot overlap this
      // interval when its end is already at or before their start.
      for (final previous in active) {
        if ((previous.createdDate ?? previous.createdAt) >= nextEnd) break;
        final conflictKey = _overlappingRecurrencePairKey(previous, next);
        if (conflictKey != null) conflictKeys.add(conflictKey);
      }

      if (nextEnd > nextStart) active.add(next);
    }
  }

  String? _overlappingRecurrencePairKey(TodoItem previous, TodoItem next) {
    final previousStart = previous.createdDate ?? previous.createdAt;
    final previousEnd = previous.dueDate?.millisecondsSinceEpoch;
    final nextStart = next.createdDate ?? next.createdAt;
    final nextEnd = next.dueDate?.millisecondsSinceEpoch;
    if (previousEnd == null || nextEnd == null) return null;
    if (previousStart >= nextEnd || nextStart >= previousEnd) return null;
    return _scheduleConflictPairKey(
      previous.id,
      previousStart,
      previousEnd,
      next.id,
      nextStart,
      nextEnd,
    );
  }

  TodoItem _copyForNextRecurrence(TodoItem source) {
    return TodoItem(
      title: source.title,
      updatedAt: source.updatedAt,
      version: source.version,
      createdDate: source.createdDate,
      recurrence: source.recurrence,
      recurrenceSeriesId: source.recurrenceSeriesId ?? source.id,
      customIntervalDays: source.customIntervalDays,
      recurrenceEndDate: source.recurrenceEndDate,
      dueDate: source.dueDate,
      remark: source.remark,
      imagePath: source.imagePath,
      originalText: source.originalText,
      groupId: source.groupId,
      reminderMinutes: source.reminderMinutes,
      teamUuid: source.teamUuid,
      creatorId: source.creatorId,
      creatorName: source.creatorName,
      teamName: source.teamName,
      collabType: source.collabType,
      isAllDay: source.isAllDay,
      categoryId: source.categoryId,
    );
  }

  void _rollRecurrenceDateByDays(TodoItem todo, int days) {
    if (todo.dueDate != null) {
      final originalDueDate = todo.dueDate!;
      todo.dueDate = DateTime(
        originalDueDate.year,
        originalDueDate.month,
        originalDueDate.day + days,
        originalDueDate.hour,
        originalDueDate.minute,
        originalDueDate.second,
        originalDueDate.millisecond,
        originalDueDate.microsecond,
      );
    }
    if (todo.createdDate != null) {
      final originalCreatedDate = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate!,
        isUtc: true,
      ).toLocal();
      todo.createdDate = DateTime(
        originalCreatedDate.year,
        originalCreatedDate.month,
        originalCreatedDate.day + days,
        originalCreatedDate.hour,
        originalCreatedDate.minute,
        originalCreatedDate.second,
        originalCreatedDate.millisecond,
      ).millisecondsSinceEpoch;
    }
  }
}
