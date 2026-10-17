import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../storage_service.dart';
import 'api_service.dart';
import 'band_sync_service.dart';
import 'float_window_service.dart';
import 'notification_service.dart';
import 'scheduled_reminder_registry.dart';
import 'pomodoro_service.dart';
import 'pomodoro_sync_service.dart';
import 'focus_do_not_disturb_service.dart';

class PomodoroStartResult {
  const PomodoroStartResult({required this.state, required this.tagNames});

  final PomodoroRunState state;
  final List<String> tagNames;
}

class PomodoroControlService {
  static Future<PomodoroStartResult> startFocus({
    required PomodoroSettings settings,
    TodoItem? boundTodo,
    List<String> tagUuids = const [],
    int currentCycle = 1,
    int? durationMinutes,
    String? planBlockId,
    String? note,
    String? deviceId,
    bool notify = true,
    bool updateFloat = true,
    bool sync = true,
    bool ensureSyncConnection = false,
    bool syncBand = true,
    bool startPaused = false,
    bool strictWaitingForFlip = false,
    bool deferSideEffects = false,
  }) async {
    final isCountUp = settings.mode == TimerMode.countUp;
    final isStrictWaiting =
        startPaused &&
        strictWaitingForFlip &&
        isCountUp &&
        settings.strictFreeFocus;
    final focusSeconds = isCountUp
        ? 0
        : (durationMinutes ?? settings.focusMinutes) * 60;
    final sessionUuid = const Uuid().v4();

    final tags = await _measureStartStage('load_tags', PomodoroService.getTags);
    final tagNames = <String>[];
    for (final uuid in tagUuids) {
      for (final tag in tags) {
        if (tag.uuid == uuid && tag.name.isNotEmpty) {
          tagNames.add(tag.name);
          break;
        }
      }
    }

    // 自动查找匹配的任务规划块。
    // 优先匹配当前时间在范围内的，其次匹配同日同 todo 的最近未来块。
    String? activePlanBlockId = planBlockId;
    if (activePlanBlockId == null && boundTodo != null) {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(StorageService.keyCurrentUser);
      if (username != null) {
        final planLookupStartedAt = DateTime.now().millisecondsSinceEpoch;
        final nowDt = DateTime.fromMillisecondsSinceEpoch(planLookupStartedAt);
        final blocks = await _measureStartStage(
          'load_plan_blocks',
          () => StorageService.getPlanBlocksByDay(username, nowDt),
        );
        activePlanBlockId = selectAutoPlanBlockId(
          blocks: blocks,
          todoId: boundTodo.id,
          now: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    // Start the timer only after preparation reads have finished. The saved
    // absolute time anchor must not include tag or plan lookup latency.
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = isCountUp ? now : now + focusSeconds * 1000;

    final state = PomodoroRunState(
      phase: PomodoroPhase.focusing,
      sessionUuid: sessionUuid,
      targetEndMs: end,
      currentCycle: currentCycle,
      totalCycles: settings.cycles,
      focusSeconds: focusSeconds,
      breakSeconds: settings.breakMinutes * 60,
      todoUuid: boundTodo?.id,
      todoTitle: boundTodo?.title,
      tagUuids: tagUuids,
      tagNames: tagNames,
      sessionStartMs: now,
      plannedFocusSeconds: focusSeconds,
      mode: settings.mode,
      strictFreeFocus: settings.strictFreeFocus,
      strictWaitingForFlip: isStrictWaiting,
      doNotDisturbDuringFocus: settings.doNotDisturbDuringFocus,
      isPaused: isStrictWaiting,
      pausedAtMs: isStrictWaiting ? now : 0,
      accumulatedMs: 0,
      pauseStartMs: isStrictWaiting ? now : 0,
      pauseIntervals: isStrictWaiting ? [PauseInterval(startMs: now)] : null,
      planBlockId: activePlanBlockId,
      note: note,
    );

    // Commit the run marker before touching native DND. If the process is
    // killed in between, startup can distinguish a valid focus from a
    // half-started native side effect and clear it safely.
    await _measureStartStage(
      'save_run_state',
      () => PomodoroService.saveRunState(state),
    );

    final sideEffects = _runStartSideEffects(
      settings: settings,
      state: state,
      boundTodo: boundTodo,
      tagUuids: tagUuids,
      tagNames: tagNames,
      currentCycle: currentCycle,
      durationSeconds: focusSeconds,
      activePlanBlockId: activePlanBlockId,
      note: note,
      deviceId: deviceId,
      notify: notify,
      updateFloat: updateFloat,
      sync: sync,
      ensureSyncConnection: ensureSyncConnection,
      syncBand: syncBand,
      isCountUp: isCountUp,
      isStrictWaiting: isStrictWaiting,
      now: now,
      end: end,
      bestEffort: deferSideEffects,
    );
    if (deferSideEffects) {
      unawaited(_logDeferredStartSideEffects(sideEffects, sessionUuid));
    } else {
      await sideEffects;
    }

    return PomodoroStartResult(state: state, tagNames: tagNames);
  }

  static Future<void> _runStartSideEffects({
    required PomodoroSettings settings,
    required PomodoroRunState state,
    required TodoItem? boundTodo,
    required List<String> tagUuids,
    required List<String> tagNames,
    required int currentCycle,
    required int durationSeconds,
    required String? activePlanBlockId,
    required String? note,
    required String? deviceId,
    required bool notify,
    required bool updateFloat,
    required bool sync,
    required bool ensureSyncConnection,
    required bool syncBand,
    required bool isCountUp,
    required bool isStrictWaiting,
    required int now,
    required int end,
    required bool bestEffort,
  }) async {
    final sessionUuid = state.sessionUuid;
    PomodoroSyncService.instance.setLocalFocusing(true);

    await _runStartSideEffect(
      'set_do_not_disturb',
      () => FocusDoNotDisturbService.setActive(
        settings.doNotDisturbDuringFocus && !isStrictWaiting,
        sessionUuid: sessionUuid,
        untilMs: isCountUp ? null : end,
      ),
      bestEffort: bestEffort,
    );
    await _runStartSideEffect(
      'reconcile_reminders',
      NotificationService.reconcileScheduledRemindersForDoNotDisturb,
      bestEffort: bestEffort,
    );

    if (bestEffort && !await _isCurrentRun(sessionUuid)) return;

    if (notify) {
      await _runStartSideEffect(
        'update_notification',
        () => NotificationService.updatePomodoroNotification(
          remainingSeconds: isCountUp ? 0 : durationSeconds,
          phase: 'focusing',
          todoTitle: boundTodo?.title,
          currentCycle: currentCycle,
          totalCycles: settings.cycles,
          tagNames: tagNames,
          alertKey: 'pomo_start_$end',
          timerMode: isCountUp ? 'countUp' : 'countdown',
          timerAnchorMs: isStrictWaiting ? null : (isCountUp ? now : end),
          isPaused: isStrictWaiting,
        ),
        bestEffort: bestEffort,
      );
      if (bestEffort && !await _isCurrentRun(sessionUuid)) return;
      if (!isCountUp) {
        await _runStartSideEffect(
          'schedule_end_reminder',
          () async => _scheduleFocusEndReminder(
            endMs: end,
            todoTitle: boundTodo?.title,
            cycle: currentCycle,
            totalCycles: settings.cycles,
            sessionUuid: sessionUuid,
          ),
          bestEffort: bestEffort,
        );
      }
    }

    if (updateFloat) {
      if (bestEffort && !await _isCurrentRun(sessionUuid)) return;
      await _runStartSideEffect(
        'update_float_window',
        () => FloatWindowService.update(
          endMs: isCountUp ? now : end,
          title: boundTodo?.title.isNotEmpty == true
              ? boundTodo!.title
              : (isCountUp ? '自由专注' : '倒计时'),
          tags: tagNames,
          isLocal: true,
          mode: isCountUp ? 1 : 0,
          isPaused: false,
          accumulatedMs: 0,
          pauseStartMs: 0,
          note: note ?? '',
        ),
        bestEffort: bestEffort,
      );
    }

    if (sync) {
      if (ensureSyncConnection) {
        await _runStartSideEffect(
          'ensure_sync_connection',
          () => _ensureSyncConnected(deviceId),
          bestEffort: bestEffort,
        );
      }

      if (bestEffort && !await _isCurrentRun(sessionUuid)) return;
      var deviceName = '';
      await _runStartSideEffect(
        'load_device_name',
        () async => deviceName = await StorageService.getDeviceFriendlyName(),
        bestEffort: bestEffort,
      );
      if (bestEffort && !await _isCurrentRun(sessionUuid)) return;
      await _runStartSideEffect('send_start_signal', () async {
        PomodoroSyncService.instance.sendStartSignal(
          sessionUuid: sessionUuid,
          todoUuid: boundTodo?.id.isNotEmpty == true ? boundTodo!.id : null,
          todoTitle: boundTodo?.title,
          planBlockId: activePlanBlockId,
          durationSeconds: durationSeconds,
          targetEndMs: end,
          tagNames: tagNames,
          sourceDeviceName: deviceName,
          mode: settings.mode.index,
          currentCycle: currentCycle,
          totalCycles: settings.cycles,
          plannedFocusSeconds: durationSeconds,
          note: note,
          doNotDisturb: settings.doNotDisturbDuringFocus && !isStrictWaiting,
          customTimestamp: now,
        );
      }, bestEffort: bestEffort);
    }

    if (syncBand) {
      if (bestEffort && !await _isCurrentRun(sessionUuid)) return;
      await _runStartSideEffect(
        'sync_band',
        () => BandSyncService.syncPomodoro([
          {
            'sessionUuid': sessionUuid,
            'phase': PomodoroPhase.focusing.index,
            'targetEndMs': end,
            'currentCycle': currentCycle,
            'totalCycles': settings.cycles,
            'focusSeconds': durationSeconds,
            'breakSeconds': settings.breakMinutes * 60,
            'todoUuid': boundTodo?.id,
            'todoTitle': boundTodo?.title,
            'tagUuids': tagUuids,
            'tagNames': tagNames.map((name) => {'name': name}).toList(),
            'sessionStartMs': now,
            'plannedFocusSeconds': durationSeconds,
            'isCountUp': isCountUp,
            'mode': settings.mode.index,
            'note': note,
          },
        ]),
        bestEffort: bestEffort,
      );
    }
  }

  static Future<bool> _isCurrentRun(String sessionUuid) async {
    final current = await PomodoroService.loadRunState();
    return current?.sessionUuid == sessionUuid &&
        current?.phase == PomodoroPhase.focusing;
  }

  static Future<void> _runStartSideEffect(
    String stage,
    Future<void> Function() action, {
    required bool bestEffort,
  }) async {
    if (!bestEffort) {
      await _measureStartStage(stage, action);
      return;
    }
    try {
      await _measureStartStage(stage, action);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[PomodoroStart] $stage failed: $error\n$stackTrace');
      }
    }
  }

  static Future<T> _measureStartStage<T>(
    String stage,
    Future<T> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint('[PomodoroStart] $stage ${stopwatch.elapsedMilliseconds}ms');
      }
    }
  }

  static Future<void> _logDeferredStartSideEffects(
    Future<void> sideEffects,
    String sessionUuid,
  ) async {
    try {
      await sideEffects;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[PomodoroStart] deferred side effects failed for $sessionUuid: '
          '$error\n$stackTrace',
        );
      }
    }
  }

  @visibleForTesting
  static String? selectAutoPlanBlockId({
    required List<TodoPlanBlock> blocks,
    required String todoId,
    required int now,
  }) {
    final eligible = blocks
        .where(
          (b) =>
              !b.isDeleted &&
              b.todoId == todoId &&
              b.endTime > now &&
              b.status != TodoPlanStatus.finished &&
              b.status != TodoPlanStatus.skipped &&
              b.status != TodoPlanStatus.cancelled &&
              b.status != TodoPlanStatus.missed,
        )
        .toList();

    final inRange = eligible.where(
      (b) => now >= b.startTime && now < b.endTime,
    );
    if (inRange.isNotEmpty) {
      return inRange.first.uuid;
    }

    final upcoming = eligible.where((b) => b.startTime >= now).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (upcoming.isNotEmpty) {
      return upcoming.first.uuid;
    }

    return null;
  }

  static Future<bool> stopCurrentFocus({
    required String username,
    PomodoroRecordStatus status = PomodoroRecordStatus.interrupted,
    String? deviceId,
    bool markTodoComplete = false,
    bool notifyEnd = true,
    bool updateFloat = true,
    bool sync = true,
    bool ensureSyncConnection = false,
  }) async {
    final state = await PomodoroService.loadRunState();
    if (state == null ||
        state.phase == PomodoroPhase.idle ||
        state.phase == PomodoroPhase.finished) {
      return false;
    }

    await NotificationService.cancelNotification();
    await NotificationService.cancelReminder(40001);
    await NotificationService.cancelReminder(40002);

    final now = DateTime.now().millisecondsSinceEpoch;

    await PomodoroService.addRecord(
      PomodoroRecord.fromRunState(
        state: state,
        status: status,
        endMs: now,
        deviceId: deviceId,
      ),
    );

    if (markTodoComplete && state.todoUuid?.isNotEmpty == true) {
      final allTodos = await StorageService.getTodos(username);
      final idx = allTodos.indexWhere((todo) => todo.id == state.todoUuid);
      if (idx != -1) {
        allTodos[idx].isDone = true;
        allTodos[idx].markAsChanged();
        await StorageService.saveTodos(username, allTodos);
      }
    }

    PomodoroSyncService.instance.setLocalFocusing(false);
    if (sync) {
      if (ensureSyncConnection) {
        await _ensureSyncConnected(deviceId);
      }
      PomodoroSyncService.instance.sendStopSignal(
        todoUuid: state.todoUuid,
        sessionUuid: state.sessionUuid,
      );
    }
    if (updateFloat) {
      await FloatWindowService.update(endMs: 0, isLocal: true);
    }
    await PomodoroService.clearRunState();
    await NotificationService.reconcileScheduledRemindersForDoNotDisturb();

    if (notifyEnd) {
      await NotificationService.sendPomodoroEndAlert(
        alertKey: 'pomo_end_$now',
        todoTitle: state.todoTitle,
        isBreak: false,
      );
    }
    return true;
  }

  static void _scheduleFocusEndReminder({
    required int endMs,
    required String? todoTitle,
    required int cycle,
    required int totalCycles,
    required String sessionUuid,
  }) {
    NotificationService.scheduleReminders(
      [
        {
          'triggerAtMs': endMs,
          'title': '🍅 专注时间到！',
          'text': todoTitle != null && todoTitle.isNotEmpty
              ? '"$todoTitle" 专注时段已结束'
              : '本轮专注已结束，做个总结吧',
          'notifId': 40001,
          'type': 'pomodoro',
          'source': ScheduledReminderSources.pomodoro,
          'sessionUuid': sessionUuid,
        },
      ],
      clearFirst: false,
      replaceSource: ScheduledReminderSources.pomodoro,
    );
  }

  static Future<void> _ensureSyncConnected(String? deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('current_user_id')?.toString();
    final resolvedDeviceId = deviceId?.isNotEmpty == true
        ? deviceId!
        : await StorageService.getDeviceId();
    if (userId == null || resolvedDeviceId.isEmpty) return;
    await PomodoroSyncService.instance.ensureConnected(
      userId,
      'flutter_$resolvedDeviceId',
      authToken: ApiService.getToken(),
    );
  }
}
