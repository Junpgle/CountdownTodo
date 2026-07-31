import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_notification_policy.dart';

TodoItem _todo({required DateTime start, required DateTime due}) => TodoItem(
      title: '公考七日班',
      createdDate: start.toUtc().millisecondsSinceEpoch,
      dueDate: due,
    );

void main() {
  group('TodoNotificationPolicy.isInsideLiveWindow', () {
    test('opens the live reminder window relative to the deadline', () {
      final todo = _todo(
        start: DateTime(2026, 7, 15, 19),
        due: DateTime(2026, 7, 15, 22),
      );

      expect(
        TodoNotificationPolicy.isInsideLiveWindow(
          todo,
          DateTime(2026, 7, 15, 11, 37),
        ),
        isFalse,
      );
      expect(
        TodoNotificationPolicy.isInsideLiveWindow(
          todo,
          DateTime(2026, 7, 15, 18, 30),
        ),
        isFalse,
      );
      expect(
        TodoNotificationPolicy.isInsideLiveWindow(
          todo,
          DateTime(2026, 7, 15, 21, 30),
        ),
        isTrue,
      );
    });

    test('ignores a legacy start time when calculating deadline reminders', () {
      final todo = _todo(
        start: DateTime(2026, 7, 9, 19),
        due: DateTime(2026, 7, 15, 22),
      );

      expect(
        TodoNotificationPolicy.isInsideLiveWindow(
          todo,
          DateTime(2026, 7, 15, 11, 37),
        ),
        isFalse,
      );
      expect(
        TodoNotificationPolicy.isInsideLiveWindow(
          todo,
          DateTime(2026, 7, 15, 19),
        ),
        isFalse,
      );
      expect(
        TodoNotificationPolicy.isInsideLiveWindow(
          todo,
          DateTime(2026, 7, 15, 21, 30),
        ),
        isTrue,
      );
    });

    test('keeps a genuine overnight todo active after midnight', () {
      final todo = _todo(
        start: DateTime(2026, 7, 14, 23, 30),
        due: DateTime(2026, 7, 15, 1),
      );

      expect(
        TodoNotificationPolicy.isInsideLiveWindow(
          todo,
          DateTime(2026, 7, 15, 0, 30),
        ),
        isTrue,
      );
    });

    test('never shows an all-day todo as a live timed notification', () {
      final todo = _todo(
        start: DateTime(2026, 7, 15),
        due: DateTime(2026, 7, 15, 23, 59),
      );

      expect(
        TodoNotificationPolicy.isInsideLiveWindow(
          todo,
          DateTime(2026, 7, 15, 12),
        ),
        isFalse,
      );
    });
  });
}
