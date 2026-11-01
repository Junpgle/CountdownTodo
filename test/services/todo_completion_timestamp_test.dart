import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/timeline_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('TodoItem completedAt', () {
    test('toggling isDone sets and clears completedAt', () {
      final todo = TodoItem(title: '测试待办');
      expect(todo.isDone, isFalse);
      expect(todo.completedAt, isNull);

      final before = DateTime.now().millisecondsSinceEpoch;
      todo.isDone = true;
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(todo.isDone, isTrue);
      expect(todo.completedAt, isNotNull);
      expect(todo.completedAt! >= before, isTrue);
      expect(todo.completedAt! <= after, isTrue);

      todo.isDone = false;
      expect(todo.isDone, isFalse);
      expect(todo.completedAt, isNull);
    });

    test('toJson and fromJson preserves explicit completedAt', () {
      const explicitCompletedAt = 1754000000000;
      final todo = TodoItem(
        title: '已完成待办',
        isDone: true,
        completedAt: explicitCompletedAt,
      );

      final json = todo.toJson();
      expect(json['completed_at'], explicitCompletedAt);
      expect(json['completedAt'], explicitCompletedAt);

      final restored = TodoItem.fromJson(json);
      expect(restored.isDone, isTrue);
      expect(restored.completedAt, explicitCompletedAt);
    });

    test('legacy recurrence occurrence with null completed_at uses occurrence date instead of updated_at', () {
      // 模拟3个月前完成的循环待办：
      // createdDate / dueDate 是3个月前，但 updated_at 因为云同步合并被刷成今天
      final threeMonthsAgo = DateTime(2026, 8, 1, 10, 0).millisecondsSinceEpoch;
      final todaySyncedAt = DateTime(
        2026,
        11,
        1,
        20,
        16,
      ).millisecondsSinceEpoch;

      final legacyJson = {
        'uuid': 'recurrence-instance-1',
        'content': '公考七日班',
        'is_completed': 1,
        'recurrence': 1,
        'recurrence_series_id': 'series-gk-7',
        'created_date': threeMonthsAgo,
        'created_at': threeMonthsAgo,
        'updated_at': todaySyncedAt,
        // completed_at is null
      };

      final restored = TodoItem.fromJson(legacyJson);
      expect(restored.isDone, isTrue);
      expect(restored.completedAt, threeMonthsAgo);
      expect(restored.completedAt, isNot(todaySyncedAt));
    });

    test('detachedCopy preserves completedAt', () {
      const timestamp = 1754123456789;
      final todo = TodoItem(
        title: '复制测试',
        isDone: true,
        completedAt: timestamp,
      );
      final copy = todo.detachedCopy();
      expect(copy.isDone, isTrue);
      expect(copy.completedAt, timestamp);
    });

    test(
      'server sync merge preserves local completedAt when server has null',
      () {
        final local = TodoItem(
          id: 'todo-sync-1',
          title: '公考七日班',
          isDone: true,
          completedAt: 1754000000000,
          recurrenceSeriesId: 'series-1',
        );

        final incomingFromServer = TodoItem(
          id: 'todo-sync-1',
          title: '公考七日班',
          isDone: true,
          completedAt: null, // 旧服务端无此字段
          updatedAt: 1762000000000,
          recurrenceSeriesId: 'series-1',
        );

        StorageService.preserveLocalTodoSourceFieldsForTest(
          local,
          incomingFromServer,
        );

        expect(incomingFromServer.completedAt, 1754000000000);
      },
    );

    test('TimelineService excludes 3-month-old completed recurring todo synced today from today and includes it on original date', () async {
      final username = 'timeline_test_${DateTime.now().microsecondsSinceEpoch}';
      SharedPreferences.setMockInitialValues({
        'current_login_user': username,
        'current_user_id': 88,
      });

      final threeMonthsAgoDate = DateTime(2026, 8, 1, 10, 0);
      final todayDate = DateTime(2026, 11, 1, 20, 16);

      // 模拟3个月前完成的循环待办：期次日期为 2026-08-01，但因云同步合并更新，updatedAt 变成了今天 20:16
      final oldRecurringTodo = TodoItem(
        id: 'gk-7-day1',
        title: '公考七日班',
        isDone: true,
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: 'series-gk-7',
        createdDate: threeMonthsAgoDate.millisecondsSinceEpoch,
        createdAt: threeMonthsAgoDate.millisecondsSinceEpoch,
        updatedAt: todayDate.millisecondsSinceEpoch,
        completedAt: threeMonthsAgoDate.millisecondsSinceEpoch,
      );

      await StorageService.saveTodos(username, [oldRecurringTodo], sync: false);

      // 1. 查询今天的个人时间轴：不应包含该 3 个月前完成的待办
      final todayEvents = await TimelineService.instance.getEventsForDay(
        username,
        todayDate,
      );
      final todayCompleted = todayEvents
          .where((e) => e.type == TimelineEventType.todoCompleted)
          .toList();
      expect(todayCompleted, isEmpty);

      // 2. 查询 3 个月前的个人时间轴：正确展示在历史完成当天
      final oldDayEvents = await TimelineService.instance.getEventsForDay(
        username,
        threeMonthsAgoDate,
      );
      final oldCompleted = oldDayEvents
          .where((e) => e.type == TimelineEventType.todoCompleted)
          .toList();
      expect(oldCompleted.length, 1);
      expect(oldCompleted.first.subtitle, '公考七日班');
    });
  });
}
