import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_progress.dart';
import 'package:countdown_todo/services/timeline_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimelineService.summarizeHabitProgress', () {
    final today = DateTime(2026, 10, 9);

    test('active habits are counted normally', () {
      final habit1 = HabitGoal(uuid: 'h1', name: '喝水');
      final habit2 = HabitGoal(uuid: 'h2', name: '阅读');

      final progressByHabit = {
        habit1: [
          _createDay(habit1, today, planned: true, met: true, hasRecord: true),
        ],
        habit2: [
          _createDay(
            habit2,
            today,
            planned: true,
            met: false,
            finished: true,
            hasRecord: false,
          ),
        ],
      };

      final summary = TimelineService.summarizeHabitProgress(progressByHabit);

      expect(summary.habitCount, 2);
      expect(summary.plannedCount, 2);
      expect(summary.completedCount, 1);
      expect(summary.missedCount, 1);
      expect(summary.recordedCount, 1);
      expect(summary.completionRate, 0.5);
    });

    test('archived habits without records or met goals are excluded from planned count', () {
      final active1 = HabitGoal(uuid: 'h1', name: '喝水');
      final active2 = HabitGoal(uuid: 'h2', name: '跑步');

      final archived1 = HabitGoal(uuid: 'h3', name: '背单词', isArchived: true);
      final archived2 = HabitGoal(uuid: 'h4', name: '冥想', isArchived: true);
      final archived3 = HabitGoal(uuid: 'h5', name: '俯卧撑', isArchived: true);
      final archived4 = HabitGoal(uuid: 'h6', name: '早起', isArchived: true);
      final archived5 = HabitGoal(uuid: 'h7', name: '写日记', isArchived: true);

      final progressByHabit = {
        active1: [
          _createDay(active1, today, planned: true, met: true, hasRecord: true),
        ],
        active2: [
          _createDay(
            active2,
            today,
            planned: true,
            met: false,
            finished: false,
            hasRecord: false,
          ),
        ],
        archived1: [
          _createDay(
            archived1,
            today,
            planned: true,
            met: false,
            hasRecord: false,
          ),
        ],
        archived2: [
          _createDay(
            archived2,
            today,
            planned: true,
            met: false,
            hasRecord: false,
          ),
        ],
        archived3: [
          _createDay(
            archived3,
            today,
            planned: true,
            met: false,
            hasRecord: false,
          ),
        ],
        archived4: [
          _createDay(
            archived4,
            today,
            planned: true,
            met: false,
            hasRecord: false,
          ),
        ],
        archived5: [
          _createDay(
            archived5,
            today,
            planned: true,
            met: false,
            hasRecord: false,
          ),
        ],
      };

      final summary = TimelineService.summarizeHabitProgress(progressByHabit);

      // Only the 2 active habits are counted in habitCount and plannedCount (1/2, not 1/7).
      expect(summary.habitCount, 2);
      expect(summary.plannedCount, 2);
      expect(summary.completedCount, 1);
      expect(summary.missedCount, 0);
      expect(summary.recordedCount, 1);
      expect(summary.completionRate, 0.5);
    });

    test('archived habits with historical records in range are retained in summary', () {
      final active = HabitGoal(uuid: 'h1', name: '喝水');
      final archived = HabitGoal(uuid: 'h2', name: '跑步', isArchived: true);

      final progressByHabit = {
        active: [
          _createDay(active, today, planned: true, met: true, hasRecord: true),
        ],
        archived: [
          _createDay(
            archived,
            today,
            planned: true,
            met: true,
            hasRecord: true,
          ),
        ],
      };

      final summary = TimelineService.summarizeHabitProgress(progressByHabit);

      expect(summary.habitCount, 2);
      expect(summary.plannedCount, 2);
      expect(summary.completedCount, 2);
      expect(summary.recordedCount, 2);
      expect(summary.completionRate, 1.0);
    });
  });
}

HabitDayProgress _createDay(
  HabitGoal habit,
  DateTime date, {
  bool planned = true,
  bool met = false,
  bool finished = true,
  bool hasRecord = false,
  bool isSkipped = false,
}) {
  final progress = HabitProgress(
    period: date,
    currentValue: met ? 100 : (hasRecord ? 50 : 0),
    targetValue: 100,
    completionRatio: met ? 1.0 : (hasRecord ? 0.5 : 0.0),
    hasRecord: hasRecord,
    goalMet: met,
    isPlanned: planned,
    isFinished: finished,
    isSkipped: isSkipped,
  );
  return HabitDayProgress(
    habit: habit,
    logicalDate: date,
    status: progress.dayStatus,
    progress: progress,
  );
}
