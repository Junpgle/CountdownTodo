import 'package:countdown_todo/features/habits/repositories/habit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HabitRepository.reminderStartFor（18.1 完成型固定提醒映射）', () {
    test('把一天内分钟数映射为当天本地时刻', () {
      final start = HabitRepository.reminderStartFor(
        DateTime(2026, 8, 5),
        22 * 60,
      );
      expect(start, DateTime(2026, 8, 5, 22, 0));
    });

    test('跨午夜边界（04:30）映射正确', () {
      final start = HabitRepository.reminderStartFor(
        DateTime(2026, 8, 5),
        4 * 60 + 30,
      );
      expect(start, DateTime(2026, 8, 5, 4, 30));
    });

    test('越界分钟数被钳制在 0..1439', () {
      final under = HabitRepository.reminderStartFor(
        DateTime(2026, 8, 5),
        -10,
      );
      expect(under, DateTime(2026, 8, 5, 0, 0));
      final over = HabitRepository.reminderStartFor(
        DateTime(2026, 8, 5),
        1500,
      );
      expect(over, DateTime(2026, 8, 5, 23, 59));
    });
  });
}
