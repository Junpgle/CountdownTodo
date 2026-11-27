part of '../lan_sync_service_io.dart';

mixin _LanSyncMergeMixin on _LanSyncServiceBase {
  List<Map<String, dynamic>> _extractList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Future<
    ({
      int todos,
      int countdowns,
      int timeLogs,
      int pomodoroTags,
      int pomodoroRecords,
      int courses,
    })
  >
  _mergeSyncBundle({
    required String username,
    required Map<String, dynamic> data,
    required LanSyncConfig config,
    bool emitProgress = true,
  }) {
    final prev = _mergeLock;
    final completer =
        Completer<
          ({
            int todos,
            int countdowns,
            int timeLogs,
            int pomodoroTags,
            int pomodoroRecords,
            int courses,
          })
        >();
    _mergeLock = completer.future.then((_) {}, onError: (_) {});

    () async {
      try {
        await prev;
        final result = await _mergeSyncBundleLocked(
          username: username,
          data: data,
          config: config,
          emitProgress: emitProgress,
        );
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }();

    return completer.future;
  }

  Future<
    ({
      int todos,
      int countdowns,
      int timeLogs,
      int pomodoroTags,
      int pomodoroRecords,
      int courses,
    })
  >
  _mergeSyncBundleLocked({
    required String username,
    required Map<String, dynamic> data,
    required LanSyncConfig config,
    bool emitProgress = true,
  }) async {
    int todosSynced = 0;
    int countdownsSynced = 0;
    int timeLogsSynced = 0;
    int pomodoroTagsSynced = 0;
    int pomodoroRecordsSynced = 0;
    int coursesSynced = 0;

    final step = config.totalCount > 0 ? 0.4 / config.totalCount : 0.1;
    double progress = 0.5;

    if (config.syncTodos) {
      await _mergeTodos(
        username,
        _extractList(data['todos']),
        (c) => todosSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并待办完成...');
      }
    }

    if (config.syncCountdowns) {
      await _mergeCountdowns(
        username,
        _extractList(data['countdowns']),
        (c) => countdownsSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并倒数日完成...');
      }
    }

    if (config.syncTimeLogs) {
      await _mergeTimeLogs(
        username,
        _extractList(data['timeLogs']),
        (c) => timeLogsSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并时间日志完成...');
      }
    }

    if (config.syncPomodoroTags) {
      await _mergePomodoroTags(
        _extractList(data['pomodoroTags']),
        (c) => pomodoroTagsSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并番茄标签完成...');
      }
    }

    if (config.syncPomodoroRecords) {
      await _mergePomodoroRecords(
        _extractList(data['pomodoroRecords']),
        (c) => pomodoroRecordsSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并番茄记录完成...');
      }
    }

    if (config.syncCourses) {
      await _mergeCourses(
        username,
        _extractList(data['courses']),
        (c) => coursesSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并课程完成...');
      }
    }

    if (config.syncSecrets && data['secrets'] is Map) {
      await LanSyncPrivateData.mergeSecrets(
        Map<String, dynamic>.from(data['secrets'] as Map),
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并密钥与 AI 配置完成...');
      }
    }

    if (config.syncSettings && data['settings'] is Map) {
      await LanSyncPrivateData.mergePortableSettings(
        Map<String, dynamic>.from(data['settings'] as Map),
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并偏好设置完成...');
      }
    }

    return (
      todos: todosSynced,
      countdowns: countdownsSynced,
      timeLogs: timeLogsSynced,
      pomodoroTags: pomodoroTagsSynced,
      pomodoroRecords: pomodoroRecordsSynced,
      courses: coursesSynced,
    );
  }

  @override
  Future<void> _mergeTodos(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final local = await StorageService.getTodos(username, includeDeleted: true);
    final Map<String, TodoItem> merged = {for (var t in local) t.id: t};
    bool changed = false;
    for (var r in remote) {
      final remoteItem = TodoItem.fromJson(r);
      final existing = merged[remoteItem.id];
      if (existing == null) {
        if (!remoteItem.isDeleted) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      } else {
        if (_lwwWins(remoteItem, existing)) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      }
    }
    if (changed) {
      await StorageService.saveTodos(
        username,
        merged.values.toList(),
        sync: false,
      );
      onChanged(merged.length);
    }
  }

  @override
  Future<void> _mergeCountdowns(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final local = await StorageService.getCountdowns(
      username,
      includeDeleted: true,
    );
    final Map<String, CountdownItem> merged = {for (var c in local) c.id: c};
    bool changed = false;
    for (var r in remote) {
      final remoteItem = CountdownItem.fromJson(r);
      final existing = merged[remoteItem.id];
      if (existing == null) {
        if (!remoteItem.isDeleted) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      } else {
        if (_lwwWinsCountdown(remoteItem, existing)) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      }
    }
    if (changed) {
      await StorageService.saveCountdowns(
        username,
        merged.values.toList(),
        sync: false,
      );
      onChanged(merged.length);
    }
  }

  @override
  Future<void> _mergeTimeLogs(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final local = await StorageService.getTimeLogs(username);
    final Map<String, TimeLogItem> merged = {for (var t in local) t.id: t};
    bool changed = false;
    for (var r in remote) {
      final remoteItem = TimeLogItem.fromJson(r);
      final existing = merged[remoteItem.id];
      if (existing == null) {
        if (!remoteItem.isDeleted) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      } else {
        if (_lwwWinsTimeLog(remoteItem, existing)) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      }
    }
    if (changed) {
      await StorageService.saveTimeLogs(
        username,
        merged.values.toList(),
        sync: false,
      );
      onChanged(merged.length);
    }
  }

  @override
  Future<void> _mergePomodoroTags(
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final localAll = await PomodoroService.getAllTagsIncludingDeleted();
    final Map<String, PomodoroTag> merged = {for (var t in localAll) t.uuid: t};
    bool changed = false;
    for (var r in remote) {
      final remoteTag = PomodoroTag.fromJson(r);
      final existing = merged[remoteTag.uuid];
      if (existing == null) {
        if (!remoteTag.isDeleted) {
          merged[remoteTag.uuid] = remoteTag;
          changed = true;
        }
      } else {
        if (remoteTag.updatedAt > existing.updatedAt) {
          merged[remoteTag.uuid] = remoteTag;
          changed = true;
        }
      }
    }
    if (changed) {
      await PomodoroService.saveTags(merged.values.toList());
      onChanged(merged.length);
    }
  }

  @override
  Future<void> _mergePomodoroRecords(
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final remoteRecords = remote.map(PomodoroRecord.fromJson).toList();
    final changed = await PomodoroService.mergeRecordsLww(remoteRecords);
    if (changed) {
      onChanged(remoteRecords.length);
    }
  }

  @override
  Future<void> _mergeCourses(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final local = await CourseService.getAllCourses(
      username,
      applyCalendarAdjustments: false,
    );
    final remoteCourses = remote.map(CourseItem.fromJson).toList();
    final merged = CourseScheduleSemantics.mergeBySlot(local, remoteCourses);
    final localByUuid = {for (final course in local) course.uuid: course};

    bool sameCourse(CourseItem left, CourseItem right) =>
        left.courseName == right.courseName &&
        left.teacherName == right.teacherName &&
        left.date == right.date &&
        left.weekday == right.weekday &&
        left.startTime == right.startTime &&
        left.endTime == right.endTime &&
        left.weekIndex == right.weekIndex &&
        left.roomName == right.roomName &&
        left.lessonType == right.lessonType &&
        left.semesterId == right.semesterId &&
        left.teamUuid == right.teamUuid &&
        left.version == right.version &&
        left.updatedAt == right.updatedAt &&
        left.isDeleted == right.isDeleted;

    final changed =
        merged.length != local.length ||
        merged.any((course) {
          final old = localByUuid[course.uuid];
          return old == null || !sameCourse(old, course);
        });
    if (changed) {
      await CourseService.saveCourses(username, merged);
      onChanged(merged.length);
    }
  }

  bool _lwwWins(TodoItem remote, TodoItem local) =>
      LanSyncLww.isTodoWinner(remote, local);

  bool _lwwWinsCountdown(CountdownItem remote, CountdownItem local) =>
      LanSyncLww.isCountdownWinner(remote, local);

  bool _lwwWinsTimeLog(TimeLogItem remote, TimeLogItem local) =>
      LanSyncLww.isTimeLogWinner(remote, local);

  @override
  Future<Map<String, dynamic>> _gatherLocalData(
    String username, [
    LanSyncConfig? config,
  ]) async {
    config ??= LanSyncConfig();
    final todos = config.syncTodos
        ? await StorageService.getTodos(username, includeDeleted: true)
        : [];
    final countdowns = config.syncCountdowns
        ? await StorageService.getCountdowns(username, includeDeleted: true)
        : [];
    final timeLogs = config.syncTimeLogs
        ? await StorageService.getTimeLogs(username)
        : [];
    final pomodoroTags = config.syncPomodoroTags
        ? await PomodoroService.getAllTagsIncludingDeleted()
        : [];
    final pomodoroRecords = config.syncPomodoroRecords
        ? await PomodoroService.getRecords()
        : [];
    final courses = config.syncCourses
        ? await CourseService.getAllCourses(username)
        : [];
    final secrets = config.syncSecrets
        ? await LanSyncPrivateData.gatherSecrets()
        : null;
    final settings = config.syncSettings
        ? await LanSyncPrivateData.gatherPortableSettings()
        : null;

    return {
      'todos': todos.map((t) => t.toJson()).toList(),
      'countdowns': countdowns.map((c) => c.toJson()).toList(),
      'timeLogs': timeLogs.map((t) => t.toJson()).toList(),
      'pomodoroTags': pomodoroTags.map((t) => t.toJson()).toList(),
      'pomodoroRecords': pomodoroRecords.map((r) => r.toJson()).toList(),
      'courses': courses.map((c) => c.toJson()).toList(),
      if (secrets != null && secrets.isNotEmpty) 'secrets': secrets,
      if (settings != null && settings.isNotEmpty) 'settings': settings,
    };
  }
}
