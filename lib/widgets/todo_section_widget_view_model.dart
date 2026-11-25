part of 'todo_section_widget.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _TodoSectionViewModelMixin on _TodoSectionStateBase {
  _TodoSectionViewModel _computeViewModel() {
    final bool hideFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.hidden;
    final bool separateFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.separate;

    final DateTime now = widget.clock();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final seriesOccurrences = <String, List<TodoItem>>{};
    for (final todo in widget.todos) {
      final seriesId = todo.recurrenceSeriesId;
      if (todo.isDeleted || seriesId == null || seriesId.isEmpty) continue;
      if (_habitOnlyRecurringSeriesIds.contains(seriesId)) continue;
      if (_selectedSubTeamUuid != null &&
          todo.teamUuid != _selectedSubTeamUuid) {
        continue;
      }
      seriesOccurrences.putIfAbsent(seriesId, () => []).add(todo);
    }
    for (final occurrences in seriesOccurrences.values) {
      occurrences.sort(
        (a, b) => (a.createdDate ?? a.createdAt).compareTo(
          b.createdDate ?? b.createdAt,
        ),
      );
    }
    _recurrenceSeriesOccurrences = seriesOccurrences;

    final seriesRepresentativeIds = _buildRecurrenceSeriesRepresentativeIds(
      seriesOccurrences,
      occurrencesSortedByStart: true,
    );

    // Build groupById map for O(1) lookup - avoid todoGroups.any() per todo
    final groupById = <String, TodoGroup>{};
    if (!hideFolders) {
      for (final g in widget.todoGroups) {
        if (g.isDeleted) continue;
        if (_selectedSubTeamUuid != null &&
            g.teamUuid != _selectedSubTeamUuid) {
          continue;
        }
        groupById[g.id] = g;
      }
    }

    // Build todosByGroup map and orphaned list in one pass
    final todosByGroup = <String, List<TodoItem>>{};
    final orphanedTodos = <TodoItem>[];
    var activeTodoCount = 0;
    var undoneCount = 0;
    for (final t in widget.todos) {
      if (t.isDeleted || t.isSkipped || _isHistoricalTodoAt(t, today)) continue;
      if (_habitOnlyRecurringSeriesIds.isNotEmpty) {
        final seriesId = t.recurrenceSeriesId;
        if (seriesId != null &&
            seriesId.isNotEmpty &&
            _habitOnlyRecurringSeriesIds.contains(seriesId)) {
          continue;
        }
      }
      if (_selectedSubTeamUuid != null && t.teamUuid != _selectedSubTeamUuid) {
        continue;
      }
      if (!_shouldDisplayRecurrenceTodo(t, seriesRepresentativeIds)) {
        continue;
      }

      activeTodoCount++;
      final tid = t.groupId;
      if (!hideFolders &&
          tid != null &&
          tid.isNotEmpty &&
          groupById.containsKey(tid)) {
        todosByGroup.putIfAbsent(tid, () => []).add(t);
      } else {
        orphanedTodos.add(t);
      }
      if (!t.isDone) undoneCount++;
    }

    final Iterable<TodoGroup> activeGroups = hideFolders
        ? const <TodoGroup>[]
        : groupById.values;

    List<_SortedDisplayItem> pastItems = [];
    List<_SortedDisplayItem> todayItems = [];
    List<_SortedDisplayItem> futureItems = [];
    List<_GroupDisplayData> separateGroupData = [];

    void placeItem(_SortedDisplayItem item) {
      if (item.date == null) {
        todayItems.add(item);
      } else {
        final d = DateTime(item.date!.year, item.date!.month, item.date!.day);
        if (d.isBefore(today)) {
          pastItems.add(item);
        } else if (d.isAfter(today)) {
          futureItems.add(item);
        } else {
          todayItems.add(item);
        }
      }
    }

    // 1. Process Folders - iterate over active groups (already filtered)
    for (final g in activeGroups) {
      final gTodos = todosByGroup[g.id] ?? [];

      if (gTodos.isEmpty) continue;

      var isAllDone = true;
      DateTime? earliestUndoneDate;
      DateTime? earliestAnyDate;
      var groupProgress = 0.0;
      for (var t in gTodos) {
        if (!t.isDone) isAllDone = false;

        final dueDate = t.dueDate;
        if (dueDate != null) {
          if (earliestAnyDate == null || dueDate.isBefore(earliestAnyDate)) {
            earliestAnyDate = dueDate;
          }
          if (!t.isDone &&
              (earliestUndoneDate == null ||
                  dueDate.isBefore(earliestUndoneDate))) {
            earliestUndoneDate = dueDate;
          }
        }

        final end = t.effectiveDueAt;
        if (t.isDone || end == null) continue;

        final cDate = DateTime.fromMillisecondsSinceEpoch(
          t.createdDate ?? t.createdAt,
          isUtc: true,
        ).toLocal();
        final totalMin = end.difference(cDate).inMinutes;
        if (totalMin > 0 && now.isAfter(cDate)) {
          final progress = (now.difference(cDate).inMinutes / totalMin).clamp(
            0.0,
            1.0,
          );
          if (progress > groupProgress) groupProgress = progress;
        }
      }
      final minDate = earliestUndoneDate ?? earliestAnyDate;

      final groupData = _GroupDisplayData(
        group: g,
        todos: gTodos,
        isAllDone: isAllDone,
        minDate: minDate,
        progress: groupProgress,
      );

      if (!separateFolders) {
        placeItem(
          _SortedDisplayItem(
            todo: null,
            group: g,
            date: minDate,
            isDone: isAllDone,
            startMs: 0,
            progress: groupProgress,
            groupTodos: gTodos,
          ),
        );
      } else {
        separateGroupData.add(groupData);
      }
    }

    // 2. Process Standalone/Orphaned Todos
    for (final t in orphanedTodos) {
      double todoProgress = 0.0;
      if (t.dueDate != null) {
        final cDate = DateTime.fromMillisecondsSinceEpoch(
          t.createdDate ?? t.createdAt,
          isUtc: true,
        ).toLocal();
        final end = t.effectiveDueAt!;
        final totalMin = end.difference(cDate).inMinutes;
        if (totalMin > 0 && now.isAfter(cDate)) {
          todoProgress = (now.difference(cDate).inMinutes / totalMin).clamp(
            0.0,
            1.0,
          );
        }
      }

      placeItem(
        _SortedDisplayItem(
          todo: t,
          group: null,
          date: t.dueDate,
          isDone: t.isDone,
          startMs: t.createdDate ?? t.createdAt,
          progress: todoProgress,
        ),
      );
    }

    void sortItems(List<_SortedDisplayItem> list) {
      list.sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final progressCmp = b.progress.compareTo(a.progress);
        if (progressCmp != 0) return progressCmp;
        if (a.date != null && b.date != null) return a.date!.compareTo(b.date!);
        if (a.date != null) return -1;
        if (b.date != null) return 1;
        return 0;
      });
    }

    sortItems(pastItems);
    sortItems(todayItems);
    sortItems(futureItems);

    return _TodoSectionViewModel(
      today: today,
      activeTodoCount: activeTodoCount,
      activeGroups: activeGroups,
      undoneCount: undoneCount,
      pastItems: pastItems,
      todayItems: todayItems,
      futureItems: futureItems,
      separateGroupData: separateGroupData,
    );
  }

  /// The dashboard revision keeps validation O(1). Other callers fall back to
  /// hashing mutable fields and identities to detect in-place changes.
  int _computeViewModelSignature(DateTime today) {
    final dataRevision = widget.dataRevision;
    if (dataRevision != null) {
      return Object.hash(
        today.millisecondsSinceEpoch,
        _selectedSubTeamUuid,
        _folderDisplayMode.index,
        dataRevision,
        identityHashCode(widget.todos),
        identityHashCode(widget.todoGroups),
      );
    }

    return Object.hash(
      today.millisecondsSinceEpoch,
      _selectedSubTeamUuid,
      _folderDisplayMode.index,
      Object.hashAll(
        widget.todos.map(
          (todo) => Object.hash(
            todo.id,
            identityHashCode(todo),
            todo.isDeleted,
            todo.isDone,
            todo.isSkipped,
            todo.version,
            todo.teamUuid,
            todo.teamName,
          ),
        ),
      ),
      Object.hashAll(
        widget.todoGroups.map(
          (group) => Object.hash(
            group.id,
            identityHashCode(group),
            group.isDeleted,
            group.version,
            group.teamUuid,
            group.teamName,
          ),
        ),
      ),
    );
  }
}
