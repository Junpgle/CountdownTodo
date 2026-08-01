part of 'storage_service.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _StorageConflict on _StorageServiceBase {
  bool recomputeLocalTodoScheduleConflictsForTest(
    List<TodoItem> todos,
  ) =>
      _recomputeLocalTodoScheduleConflicts(todos);
  bool _recomputeLocalTodoScheduleConflicts(
    List<TodoItem> todos, {
    Set<String> ignoredScheduleConflictKeys = const <String>{},
    Set<String> skipIds = const <String>{},
    void Function(int current, int total, String message)? onProgress,
  }) {
    final buckets = <String, List<_TodoInterval>>{};
    final eligibleTodos = <TodoItem>[];

    for (final todo in todos) {
      final dueDate = todo.dueDate;
      final startMs = todo.createdDate ?? todo.createdAt;
      final endMs = dueDate?.millisecondsSinceEpoch ?? 0;

      if (todo.isDeleted || dueDate == null || todo.isDateOnly) {
        continue;
      }

      if (startMs <= 0 || endMs <= 0 || startMs >= endMs) continue;

      final startDay = _localDayKey(startMs);
      final endDay = _localDayKey(endMs);
      if (startDay != endDay) continue;
      eligibleTodos.add(todo);

      buckets.putIfAbsent(startDay, () => <_TodoInterval>[]).add(
            _TodoInterval(todo: todo, startMs: startMs, endMs: endMs),
          );
    }

    onProgress?.call(
      0,
      eligibleTodos.length,
      '正在分析 ${eligibleTodos.length} 条待办',
    );

    final conflictMap = <String, List<Map<String, dynamic>>>{};
    var processed = 0;
    for (final bucket in buckets.values) {
      bucket.sort((a, b) => a.startMs.compareTo(b.startMs));
      for (var i = 0; i < bucket.length; i++) {
        for (var j = i + 1; j < bucket.length; j++) {
          final a = bucket[i];
          final b = bucket[j];
          if (b.startMs >= a.endMs) break;
          if (a.startMs < b.endMs && b.startMs < a.endMs) {
            if (_isSameRecurrenceSeries(a.todo, b.todo)) continue;
            final conflictKey = _scheduleConflictPairKey(
              a.todo.id,
              a.startMs,
              a.endMs,
              b.todo.id,
              b.startMs,
              b.endMs,
            );
            if (ignoredScheduleConflictKeys.contains(conflictKey)) continue;
            conflictMap
                .putIfAbsent(a.todo.id, () => <Map<String, dynamic>>[])
                .add(_conflictPeerSummary(b));
            conflictMap
                .putIfAbsent(b.todo.id, () => <Map<String, dynamic>>[])
                .add(_conflictPeerSummary(a));
          }
        }
        processed++;
        onProgress?.call(
          processed,
          eligibleTodos.length,
          '正在扫描 ${bucket[i].todo.title}',
        );
      }
    }

    var changed = false;
    for (final todo in todos) {
      final existing = todo.serverVersionData;
      final isLocalScheduleConflict = _isLocalScheduleConflict(existing);
      if (todo.isDeleted) {
        if (isLocalScheduleConflict || todo.hasConflict) {
          todo.hasConflict = false;
          todo.serverVersionData = null;
          changed = true;
        }
        continue;
      }

      final peers = conflictMap[todo.id];

      // Skip re-flagging items whose conflict was just resolved in this sync cycle
      if (skipIds.contains(todo.id) && peers != null && peers.isNotEmpty) {
        continue;
      }

      if (peers != null && peers.isNotEmpty) {
        if (!_hasVersionConflict(existing)) {
          final bool isTeamTodo =
              todo.teamUuid != null && todo.teamUuid!.isNotEmpty;
          final relationType = _classifyScheduleRelation(
              todo, peers.cast<Map<String, dynamic>>());
          final data = {
            'uuid': todo.id,
            'id': todo.id,
            'content': todo.title,
            'team_uuid': todo.teamUuid,
            'schedule_scope': isTeamTodo ? 'team' : 'personal',
            'relation_type': relationType,
            'conflict_kind': 'logic',
            'conflict_type': 'local_schedule_conflict',
            'source': 'local_detector',
            'start_time': todo.createdDate ?? todo.createdAt,
            'end_time': todo.dueDate?.millisecondsSinceEpoch,
            'conflict_with': peers,
          };
          if (!todo.hasConflict || jsonEncode(existing) != jsonEncode(data)) {
            todo.hasConflict = true;
            todo.serverVersionData = data;
            changed = true;
          }
        } else if (!todo.hasConflict) {
          todo.hasConflict = true;
          changed = true;
        }
      } else if (isLocalScheduleConflict) {
        todo.hasConflict = false;
        todo.serverVersionData = null;
        changed = true;
      }
    }

    return changed;
  }

  bool _clearLocalTodoScheduleConflicts(List<TodoItem> todos) {
    var changed = false;
    for (final todo in todos) {
      if (!_isLocalScheduleConflict(todo.serverVersionData)) continue;
      todo.hasConflict = false;
      todo.serverVersionData = null;
      changed = true;
    }
    return changed;
  }

  String _scheduleConflictPairKey(
    String aId,
    int aStart,
    int aEnd,
    String bId,
    int bStart,
    int bEnd,
  ) {
    final left = '$aId@$aStart-$aEnd';
    final right = '$bId@$bStart-$bEnd';
    return left.compareTo(right) <= 0 ? '$left|$right' : '$right|$left';
  }

  String? _scheduleConflictKeyFromPayload(
      TodoItem item, Map<String, dynamic> peer) {
    if (_isSameRecurrenceSeriesPayload(item, peer)) return null;
    final itemEnd = item.dueDate?.millisecondsSinceEpoch;
    final peerId = (peer['uuid'] ?? peer['id'] ?? '').toString();
    final peerStart = _parseMillis(peer['start_time'] ??
        peer['created_date'] ??
        peer['createdDate'] ??
        peer['created_at']);
    final peerEnd =
        _parseMillis(peer['end_time'] ?? peer['due_date'] ?? peer['dueDate']);
    if (itemEnd == null ||
        peerId.isEmpty ||
        peerStart == null ||
        peerEnd == null) {
      return null;
    }
    return _scheduleConflictPairKey(
      item.id,
      item.createdDate ?? item.createdAt,
      itemEnd,
      peerId,
      peerStart,
      peerEnd,
    );
  }

  int? _parseMillis(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  bool _isSameRecurrenceSeries(TodoItem first, TodoItem second) {
    final firstSeries = first.recurrenceSeriesId;
    final secondSeries = second.recurrenceSeriesId;
    return firstSeries != null &&
        firstSeries.isNotEmpty &&
        secondSeries != null &&
        secondSeries.isNotEmpty &&
        firstSeries == secondSeries;
  }

  bool _isRecurringTodoForLww(TodoItem todo) =>
      todo.recurrence != RecurrenceType.none ||
      (todo.recurrenceSeriesId?.trim().isNotEmpty ?? false);
  bool _isSameRecurrenceSeriesPayload(
    TodoItem item,
    Map<String, dynamic> peer,
  ) {
    final itemSeries = item.recurrenceSeriesId;
    final peerSeries =
        (peer['recurrence_series_id'] ?? peer['recurrenceSeriesId'])
            ?.toString();
    return itemSeries != null &&
        itemSeries.isNotEmpty &&
        peerSeries != null &&
        peerSeries.isNotEmpty &&
        itemSeries == peerSeries;
  }

  bool _hasVersionConflict(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    final type = data['conflict_type']?.toString();
    final kind = data['conflict_kind']?.toString();
    final source = data['source']?.toString();
    return type == 'version_conflict' ||
        kind == 'version' ||
        (type != 'local_schedule_conflict' && source != 'local_detector');
  }

  List<TodoItem> clearResolvedRecurrenceMigrationConflictsForTest(
    List<TodoItem> todos,
  ) =>
      _clearResolvedRecurrenceMigrationConflicts(todos);
  List<TodoItem> _clearResolvedRecurrenceMigrationConflicts(
    List<TodoItem> todos,
  ) {
    final resolved = <TodoItem>[];
    for (final todo in todos) {
      if (!todo.hasConflict ||
          todo.recurrenceSeriesId?.isNotEmpty != true ||
          !_hasVersionConflict(todo.serverVersionData) ||
          _isLocalScheduleConflict(todo.serverVersionData)) {
        continue;
      }
      final server = todo.serverVersionData!;
      final serverUuid = (server['uuid'] ?? server['id'])?.toString();
      if (serverUuid != null &&
          serverUuid.isNotEmpty &&
          serverUuid != todo.id) {
        continue;
      }
      final serverSeriesId =
          (server['recurrence_series_id'] ?? server['recurrenceSeriesId'])
              ?.toString()
              .trim();
      if (serverSeriesId != null &&
          serverSeriesId.isNotEmpty &&
          serverSeriesId != todo.recurrenceSeriesId) {
        continue;
      }

      final local = todo.toJson();
      final fields = <String>[
        'content',
        if (todo.collabType == 0) 'is_completed',
        'is_deleted',
        'due_date',
        'created_date',
        'recurrence',
        'custom_interval_days',
        'recurrence_end_date',
        'remark',
        'group_id',
        'team_uuid',
        'category_id',
        'collab_type',
        'reminder_minutes',
        'is_all_day',
      ];
      if (_hasSubstantialChange(server, local, fields)) continue;

      todo.hasConflict = false;
      todo.serverVersionData = null;
      todo.markAsChanged();
      resolved.add(todo);
    }
    return resolved;
  }

  bool _payloadHasConflict(Map<String, dynamic> data) {
    final raw = data['has_conflict'] ?? data['hasConflict'];
    return raw == 1 || raw == true || raw == '1' || raw == 'true';
  }

  bool _payloadHasVersionConflict(Map<String, dynamic> data) {
    if (!_payloadHasConflict(data)) return false;
    final rawConflictData = data['conflict_data'] ??
        data['conflictData'] ??
        data['serverVersionData'];
    Map<String, dynamic>? conflictData;
    if (rawConflictData is String && rawConflictData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawConflictData);
        if (decoded is Map) {
          conflictData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        conflictData = null;
      }
    } else if (rawConflictData is Map) {
      conflictData = Map<String, dynamic>.from(rawConflictData);
    }
    return _hasVersionConflict(conflictData);
  }

  bool _isLocalScheduleConflict(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    return data['conflict_type'] == 'local_schedule_conflict' ||
        data['source'] == 'local_detector';
  }

  Map<String, dynamic> _stripClientOnlyConflictForSync(
      Map<String, dynamic> data) {
    final result = Map<String, dynamic>.from(data);
    final rawConflictData =
        result['conflict_data'] ?? result['serverVersionData'];
    Map<String, dynamic>? conflictData;
    if (rawConflictData is String && rawConflictData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawConflictData);
        if (decoded is Map) {
          conflictData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        conflictData = null;
      }
    } else if (rawConflictData is Map) {
      conflictData = Map<String, dynamic>.from(rawConflictData);
    }

    if (_isLocalScheduleConflict(conflictData)) {
      result['has_conflict'] = 0;
      result.remove('conflict_data');
      result.remove('serverVersionData');
    }
    return result;
  }

  void _preserveLocalTodoSourceFields(TodoItem local, TodoItem incoming) {
    if (incoming.recurrenceSeriesId == null ||
        incoming.recurrenceSeriesId!.trim().isEmpty) {
      incoming.recurrenceSeriesId = local.recurrenceSeriesId;
    }
    if ((incoming.imagePath == null || incoming.imagePath!.isEmpty) &&
        local.imagePath != null &&
        local.imagePath!.isNotEmpty) {
      incoming.imagePath = local.imagePath;
    }
    if ((incoming.originalText == null || incoming.originalText!.isEmpty) &&
        local.originalText != null &&
        local.originalText!.isNotEmpty) {
      incoming.originalText = local.originalText;
    }
  }

  Set<String> repairMissingRemoteRecurrenceSeriesIdsForTest(
    List<TodoItem> incoming,
    List<TodoItem> local,
  ) =>
      _repairMissingRemoteRecurrenceSeriesIds(incoming, local);
  Set<String> _repairMissingRemoteRecurrenceSeriesIds(
    List<TodoItem> incoming,
    List<TodoItem> local,
  ) {
    final repairedIds = <String>{};
    final localById = {for (final todo in local) todo.id: todo};

    // 云端可能已被旧设备拆成非空的“子实例自建系列”。
    // 若该云端系列 ID 在本地明确是另一系列的成员，则本地
    // 稳定 UUID 关系比云端的错误非空值更可信。
    for (final todo in incoming) {
      final remoteSeriesId = todo.recurrenceSeriesId?.trim();
      final localSeriesId = localById[todo.id]?.recurrenceSeriesId?.trim();
      if (remoteSeriesId == null ||
          remoteSeriesId.isEmpty ||
          localSeriesId == null ||
          localSeriesId.isEmpty ||
          remoteSeriesId == localSeriesId) {
        continue;
      }
      final resolvedRemoteSeriesId =
          _resolveRecurrenceSeriesAlias(remoteSeriesId, localById);
      if (resolvedRemoteSeriesId == localSeriesId) {
        todo.recurrenceSeriesId = localSeriesId;
        repairedIds.add(todo.id);
      }
    }

    for (final todo in incoming) {
      if (!_isMissingRecurrenceSeriesId(todo)) continue;
      final localSeriesId = localById[todo.id]?.recurrenceSeriesId;
      if (localSeriesId != null && localSeriesId.trim().isNotEmpty) {
        todo.recurrenceSeriesId = localSeriesId;
        repairedIds.add(todo.id);
      }
    }

    // 增量响应可能只带当前锚点；把本机已经被旧同步拆散的实例也纳入候选，
    // 同 UUID 仍以本轮云端对象为准，避免产生两个活动锚点。
    final candidatesById = <String, TodoItem>{
      for (final todo in local) todo.id: todo,
      for (final todo in incoming) todo.id: todo,
    };
    final candidates = candidatesById.values.toList();

    final activeBySignature = <String, List<TodoItem>>{};
    for (final todo in candidates) {
      if (todo.isDeleted || todo.recurrence == RecurrenceType.none) continue;
      final signature = _remoteRecurrencePlanSignature(todo);
      if (signature == null) continue;
      activeBySignature.putIfAbsent(signature, () => []).add(todo);
    }

    for (final entry in activeBySignature.entries) {
      // 两个配置完全相同的活动循环无法从旧云端数据可靠区分。
      if (entry.value.length != 1) {
        for (final anchor in entry.value) {
          if (_isMissingRecurrenceSeriesId(anchor)) {
            anchor.recurrenceSeriesId = anchor.id;
            repairedIds.add(anchor.id);
          }
        }
        continue;
      }

      final anchor = entry.value.single;
      final matching = candidates.where((candidate) {
        if (candidate.isDeleted ||
            _remoteRecurrencePlanSignature(candidate) != entry.key) {
          return false;
        }
        final candidateSeriesId = candidate.recurrenceSeriesId;
        final anchorSeriesId = anchor.recurrenceSeriesId;
        if (candidateSeriesId != null &&
            candidateSeriesId.trim().isNotEmpty &&
            anchorSeriesId != null &&
            anchorSeriesId.trim().isNotEmpty &&
            candidateSeriesId != anchorSeriesId) {
          return false;
        }
        return _isRemoteOccurrenceOnRecurrence(anchor, candidate);
      }).toList()
        ..sort((a, b) => (a.createdDate ?? a.createdAt)
            .compareTo(b.createdDate ?? b.createdAt));

      final knownSeriesIds = matching
          .map((todo) => todo.recurrenceSeriesId?.trim())
          .whereType<String>()
          .where((seriesId) => seriesId.isNotEmpty)
          .toSet();
      if (knownSeriesIds.length > 1) continue;

      final seriesId = knownSeriesIds.isNotEmpty
          ? knownSeriesIds.first
          : (matching.isNotEmpty ? matching.first.id : anchor.id);
      for (final todo in matching.followedBy([anchor])) {
        if (!_isMissingRecurrenceSeriesId(todo)) continue;
        todo.recurrenceSeriesId = seriesId;
        repairedIds.add(todo.id);
      }
    }

    // 旧设备可能已经用“当时的活动实例 ID”建立了第二个系列。若该 ID
    // 本身如今明确属于另一个系列，则它只是旧链路留下的别名，统一指向
    // 当前的规范系列。这样编辑过时长的同日实例也能归队并由去重逻辑清理。
    for (var pass = 0; pass < 10; pass++) {
      var changed = false;
      for (final todo in candidates) {
        if (todo.isDeleted) continue;
        final seriesId = todo.recurrenceSeriesId;
        if (seriesId == null || seriesId.isEmpty) continue;
        final seriesAnchor = candidatesById[seriesId];
        final canonicalSeriesId = seriesAnchor?.recurrenceSeriesId;
        if (canonicalSeriesId == null ||
            canonicalSeriesId.isEmpty ||
            canonicalSeriesId == seriesId) {
          continue;
        }
        todo.recurrenceSeriesId = canonicalSeriesId;
        repairedIds.add(todo.id);
        changed = true;
      }
      if (!changed) break;
    }

    return repairedIds;
  }

  String _resolveRecurrenceSeriesAlias(
    String seriesId,
    Map<String, TodoItem> todosById,
  ) {
    var current = seriesId;
    final visited = <String>{};
    while (visited.add(current)) {
      final next = todosById[current]?.recurrenceSeriesId?.trim();
      if (next == null || next.isEmpty || next == current) break;
      current = next;
    }
    return current;
  }

  Set<String> repairLocalRecurrenceSeriesAliasesFromHistoryForTest(
    List<TodoItem> todos,
    Map<String, List<String>> historicalSeriesByTodoId,
  ) =>
      _repairLocalRecurrenceSeriesAliases(
        todos,
        historicalSeriesByTodoId,
      );
  Future<Set<String>> _repairLocalRecurrenceSeriesAliasesFromHistory(
    Database db,
    List<TodoItem> todos,
  ) async {
    final relevantIds = todos
        .where((todo) => todo.recurrenceSeriesId?.isNotEmpty == true)
        .map((todo) => todo.id)
        .toList();
    if (relevantIds.isEmpty) return <String>{};

    final historicalSeriesByTodoId = <String, List<String>>{};
    const chunkSize = 300;
    for (var offset = 0; offset < relevantIds.length; offset += chunkSize) {
      final end = (offset + chunkSize < relevantIds.length)
          ? offset + chunkSize
          : relevantIds.length;
      final chunk = relevantIds.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'op_logs',
        columns: const ['target_uuid', 'data_json', 'timestamp'],
        where: 'target_table = ? AND target_uuid IN ($placeholders)',
        whereArgs: ['todos', ...chunk],
        orderBy: 'timestamp ASC',
      );
      for (final row in rows) {
        final targetUuid = row['target_uuid']?.toString();
        final rawData = row['data_json'];
        if (targetUuid == null || targetUuid.isEmpty || rawData == null) {
          continue;
        }
        try {
          final decoded = jsonDecode(rawData.toString());
          if (decoded is! Map) continue;
          final seriesId =
              (decoded['recurrence_series_id'] ?? decoded['recurrenceSeriesId'])
                  ?.toString()
                  .trim();
          if (seriesId == null || seriesId.isEmpty) continue;
          final history = historicalSeriesByTodoId.putIfAbsent(
            targetUuid,
            () => <String>[],
          );
          history.add(seriesId);
        } catch (_) {
          // 单条旧 oplog 损坏不应阻断整体同步。
        }
      }
    }
    return _repairLocalRecurrenceSeriesAliases(
      todos,
      historicalSeriesByTodoId,
    );
  }

  Set<String> _repairLocalRecurrenceSeriesAliases(
    List<TodoItem> todos,
    Map<String, List<String>> historicalSeriesByTodoId,
  ) {
    final aliases = <String, String>{};
    for (final todo in todos) {
      final currentSeriesId = todo.recurrenceSeriesId?.trim();
      if (currentSeriesId == null ||
          currentSeriesId.isEmpty ||
          currentSeriesId != todo.id) {
        continue;
      }
      final history = (historicalSeriesByTodoId[todo.id] ?? const [])
          .map((seriesId) => seriesId.trim())
          .where((seriesId) => seriesId.isNotEmpty)
          .toList();
      final currentSeriesCount =
          history.where((seriesId) => seriesId == currentSeriesId).length;
      final previousSeriesCounts = <String, int>{};
      for (final seriesId in history) {
        if (seriesId == currentSeriesId) continue;
        previousSeriesCounts[seriesId] =
            (previousSeriesCounts[seriesId] ?? 0) + 1;
      }
      if (previousSeriesCounts.length == 1 &&
          previousSeriesCounts.values.single >= currentSeriesCount) {
        aliases[currentSeriesId] = previousSeriesCounts.keys.single;
      }
    }
    if (aliases.isEmpty) return <String>{};

    String resolve(String seriesId) {
      var current = seriesId;
      final visited = <String>{};
      while (visited.add(current)) {
        final next = aliases[current];
        if (next == null || next.isEmpty || next == current) break;
        current = next;
      }
      return current;
    }

    final repairedIds = <String>{};
    for (final todo in todos) {
      final currentSeriesId = todo.recurrenceSeriesId?.trim();
      if (currentSeriesId == null || currentSeriesId.isEmpty) continue;
      final canonicalSeriesId = resolve(currentSeriesId);
      if (canonicalSeriesId == currentSeriesId) continue;
      todo.recurrenceSeriesId = canonicalSeriesId;
      repairedIds.add(todo.id);
    }
    return repairedIds;
  }

  bool _isMissingRecurrenceSeriesId(TodoItem todo) =>
      todo.recurrenceSeriesId == null ||
      todo.recurrenceSeriesId!.trim().isEmpty;
  String? _remoteRecurrencePlanSignature(TodoItem todo) {
    final startMs = todo.createdDate;
    if (startMs == null || startMs <= 0) return null;
    final start =
        DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
    final dueMs = todo.dueDate?.millisecondsSinceEpoch;
    final durationMs = dueMs == null ? null : dueMs - startMs;
    if (durationMs != null && durationMs < 0) return null;
    final recurrenceEnd = todo.recurrenceEndDate;
    final recurrenceEndKey = recurrenceEnd == null
        ? null
        : '${recurrenceEnd.year}-${recurrenceEnd.month}-${recurrenceEnd.day}';
    return jsonEncode([
      todo.title.trim(),
      todo.remark?.trim(),
      todo.groupId,
      todo.teamUuid,
      todo.categoryId,
      todo.collabType,
      todo.isAllDay,
      todo.reminderMinutes,
      todo.customIntervalDays,
      recurrenceEndKey,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      durationMs,
    ]);
  }

  bool _isRemoteOccurrenceOnRecurrence(
    TodoItem ruleSource,
    TodoItem candidate,
  ) {
    final ruleStartMs = ruleSource.createdDate;
    final candidateStartMs = candidate.createdDate;
    if (ruleStartMs == null || candidateStartMs == null) return false;

    final ruleStart =
        DateTime.fromMillisecondsSinceEpoch(ruleStartMs, isUtc: true).toLocal();
    final candidateStart = DateTime.fromMillisecondsSinceEpoch(
      candidateStartMs,
      isUtc: true,
    ).toLocal();
    final ruleDay = DateTime(ruleStart.year, ruleStart.month, ruleStart.day);
    final candidateDay =
        DateTime(candidateStart.year, candidateStart.month, candidateStart.day);
    if (ruleSource.recurrence == RecurrenceType.weekdays &&
        (candidateDay.weekday == DateTime.saturday ||
            candidateDay.weekday == DateTime.sunday)) {
      return false;
    }
    final recurrenceEnd = ruleSource.recurrenceEndDate;
    if (recurrenceEnd != null) {
      final endDay = DateTime(
        recurrenceEnd.year,
        recurrenceEnd.month,
        recurrenceEnd.day,
      );
      if (candidateDay.isAfter(endDay)) return false;
    }
    if (candidateDay == ruleDay) return true;

    var cursor = candidateDay.isBefore(ruleDay) ? candidateStart : ruleStart;
    final target = candidateDay.isBefore(ruleDay) ? ruleDay : candidateDay;
    for (var i = 0; i < 500; i++) {
      final next = _nextRecurrenceDate(cursor, ruleSource);
      if (next == null || !next.isAfter(cursor)) return false;
      final nextDay = DateTime(next.year, next.month, next.day);
      if (nextDay == target) return true;
      if (nextDay.isAfter(target)) return false;
      cursor = next;
    }
    return false;
  }

  Map<String, dynamic> _conflictPeerSummary(_TodoInterval interval) {
    return {
      'uuid': interval.todo.id,
      'id': interval.todo.id,
      'title': interval.todo.title,
      'content': interval.todo.title,
      'team_uuid': interval.todo.teamUuid,
      'recurrence_series_id': interval.todo.recurrenceSeriesId,
      'schedule_scope':
          (interval.todo.teamUuid != null && interval.todo.teamUuid!.isNotEmpty)
              ? 'team'
              : 'personal',
      'start_time': interval.startMs,
      'end_time': interval.endMs,
    };
  }

  String _classifyScheduleRelation(
      TodoItem current, List<Map<String, dynamic>> peers) {
    final currentIsTeam =
        current.teamUuid != null && current.teamUuid!.isNotEmpty;
    final hasTeamPeer = peers.any((peer) {
      final teamUuid = peer['team_uuid']?.toString();
      return teamUuid != null && teamUuid.isNotEmpty;
    });
    final hasPersonalPeer = peers.any((peer) {
      final teamUuid = peer['team_uuid']?.toString();
      return teamUuid == null || teamUuid.isEmpty;
    });

    if ((currentIsTeam && hasPersonalPeer) || (!currentIsTeam && hasTeamPeer)) {
      return 'personal_team';
    }
    if (currentIsTeam) return 'team_team';
    return 'personal_personal';
  }

  String _localDayKey(int ms) {
    return DateFormat('yyyy-MM-dd')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));
  }
}
