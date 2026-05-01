import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage_service.dart';
import 'api_service.dart';
import 'band_sync_service.dart';
import 'float_window_service.dart';
import 'notification_service.dart';
import 'pomodoro_service.dart';
import 'pomodoro_sync_service.dart';

class PomodoroStartResult {
  const PomodoroStartResult({
    required this.state,
    required this.tagNames,
  });

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
    String? deviceId,
    bool notify = true,
    bool updateFloat = true,
    bool sync = true,
    bool ensureSyncConnection = false,
    bool syncBand = true,
  }) async {
    final isCountUp = settings.mode == TimerMode.countUp;
    final focusSeconds =
        isCountUp ? 0 : (durationMinutes ?? settings.focusMinutes) * 60;
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = isCountUp ? now : now + focusSeconds * 1000;
    final sessionUuid = const Uuid().v4();

    final tags = await PomodoroService.getTags();
    final tagNames = <String>[];
    for (final uuid in tagUuids) {
      for (final tag in tags) {
        if (tag.uuid == uuid && tag.name.isNotEmpty) {
          tagNames.add(tag.name);
          break;
        }
      }
    }

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
      sessionStartMs: now,
      plannedFocusSeconds: focusSeconds,
      mode: settings.mode,
      isPaused: false,
      pausedAtMs: 0,
      accumulatedMs: 0,
      pauseStartMs: 0,
    );

    PomodoroSyncService.instance.setLocalFocusing(true);
    if (notify) {
      await NotificationService.updatePomodoroNotification(
        remainingSeconds: isCountUp ? 0 : focusSeconds,
        phase: 'focusing',
        todoTitle: boundTodo?.title,
        currentCycle: currentCycle,
        totalCycles: settings.cycles,
        tagNames: tagNames,
        alertKey: 'pomo_start_$end',
      );
      if (!isCountUp) {
        _scheduleFocusEndReminder(
          endMs: end,
          todoTitle: boundTodo?.title,
          cycle: currentCycle,
          totalCycles: settings.cycles,
        );
      }
    }

    if (updateFloat) {
      await FloatWindowService.update(
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
      );
    }

    await PomodoroService.saveRunState(state);

    if (sync) {
      if (ensureSyncConnection) {
        await _ensureSyncConnected(deviceId);
      }
      PomodoroSyncService.instance.sendStartSignal(
        sessionUuid: sessionUuid,
        todoUuid: boundTodo?.id.isNotEmpty == true ? boundTodo!.id : null,
        todoTitle: boundTodo?.title,
        durationSeconds: focusSeconds,
        targetEndMs: end,
        tagNames: tagNames,
        mode: settings.mode.index,
        customTimestamp: now,
      );
    }

    if (syncBand) {
      await BandSyncService.syncPomodoro([
        {
          'sessionUuid': sessionUuid,
          'phase': PomodoroPhase.focusing.index,
          'targetEndMs': end,
          'currentCycle': currentCycle,
          'totalCycles': settings.cycles,
          'focusSeconds': focusSeconds,
          'breakSeconds': settings.breakMinutes * 60,
          'todoUuid': boundTodo?.id,
          'todoTitle': boundTodo?.title,
          'tagUuids': tagUuids,
          'tagNames': tagNames.map((name) => {'name': name}).toList(),
          'sessionStartMs': now,
          'plannedFocusSeconds': focusSeconds,
          'isCountUp': isCountUp,
          'mode': settings.mode.index,
        }
      ]);
    }

    return PomodoroStartResult(state: state, tagNames: tagNames);
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
    final actualSeconds =
        ((now - state.sessionStartMs) / 1000).round().clamp(0, 24 * 3600);

    await PomodoroService.addRecord(PomodoroRecord(
      uuid: state.sessionUuid,
      todoUuid: state.todoUuid,
      todoTitle: state.todoTitle,
      tagUuids: state.tagUuids,
      startTime: state.sessionStartMs,
      endTime: now,
      plannedDuration: state.plannedFocusSeconds,
      actualDuration: actualSeconds,
      status: status,
      deviceId: deviceId,
    ));

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
  }) {
    NotificationService.scheduleReminders([
      {
        'triggerAtMs': endMs,
        'title': '🍅 专注时间到！',
        'text': todoTitle != null && todoTitle.isNotEmpty
            ? '"$todoTitle" 专注时段已结束'
            : '本轮专注已结束，做个总结吧',
        'notifId': 40001,
      }
    ]);
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
