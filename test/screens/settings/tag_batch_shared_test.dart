import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/settings/widgets/tag_batch_shared.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterTagBatchPomodoros', () {
    test(
      'filters by date range, search query, extraPredicate, and sorts desc',
      () {
        final d1 = DateTime(2026, 11, 20, 9, 0).millisecondsSinceEpoch;
        final d2 = DateTime(2026, 11, 21, 14, 0).millisecondsSinceEpoch;
        final d3 = DateTime(2026, 11, 22, 8, 0).millisecondsSinceEpoch;
        final records = [
          PomodoroRecord(
            uuid: 'p1',
            todoTitle: '写周报',
            note: '算法梳理',
            tagUuids: ['t1'],
            startTime: d1,
            plannedDuration: 1500,
          ),
          PomodoroRecord(
            uuid: 'p2',
            todoTitle: '阅读源码',
            note: 'Flutter 框架',
            tagUuids: [],
            startTime: d2,
            plannedDuration: 1500,
          ),
          PomodoroRecord(
            uuid: 'p3',
            todoTitle: '算法刷题',
            tagUuids: [],
            startTime: d3,
            plannedDuration: 1500,
          ),
        ];

        final rangeResult = filterTagBatchPomodoros(
          records,
          dateRange: DateTimeRange(
            start: DateTime(2026, 11, 21),
            end: DateTime(2026, 11, 22),
          ),
          extraPredicate: (p) => p.tagUuids.isEmpty,
        );
        expect(rangeResult.map((p) => p.uuid), ['p3', 'p2']);

        final noteResult = filterTagBatchPomodoros(
          records,
          searchQuery: 'ALGO'.toLowerCase(),
        );
        expect(noteResult, isEmpty);

        final titleOrNoteResult = filterTagBatchPomodoros(
          records,
          searchQuery: '算法',
        );
        expect(titleOrNoteResult.map((p) => p.uuid), ['p3', 'p1']);
      },
    );
  });

  group('filterTagBatchTimeLogs', () {
    test('filters by title, remark, inclusive date range and sorts desc', () {
      final d1 = DateTime(2026, 11, 10, 10, 0).millisecondsSinceEpoch;
      final d2 = DateTime(2026, 11, 11, 18, 0).millisecondsSinceEpoch;
      final d3 = DateTime(2026, 11, 12, 9, 0).millisecondsSinceEpoch;
      final logs = [
        TimeLogItem(
          id: 'l1',
          title: '开会',
          remark: '需求评审',
          tagUuids: ['a'],
          startTime: d1,
          endTime: d1 + 1800000,
        ),
        TimeLogItem(
          id: 'l2',
          title: '代码评审',
          remark: '模块优化',
          tagUuids: [],
          startTime: d2,
          endTime: d2 + 1800000,
        ),
        TimeLogItem(
          id: 'l3',
          title: '健身',
          tagUuids: [],
          startTime: d3,
          endTime: d3 + 1800000,
        ),
      ];

      final filtered = filterTagBatchTimeLogs(
        logs,
        dateRange: DateTimeRange(
          start: DateTime(2026, 11, 10),
          end: DateTime(2026, 11, 11),
        ),
        searchQuery: '评审',
      );
      expect(filtered.map((l) => l.id), ['l2', 'l1']);
    });
  });

  group('toggleSelectAllRecordIds & mutateRecordTagUuids', () {
    test(
      'toggleSelectAllRecordIds selects all or clears when all selected',
      () {
        final selected = <String>{'a'};
        toggleSelectAllRecordIds(selected, ['a', 'b', 'c']);
        expect(selected, {'a', 'b', 'c'});

        toggleSelectAllRecordIds(selected, ['a', 'b', 'c']);
        expect(selected, isEmpty);
      },
    );

    test('mutateRecordTagUuids handles add, remove, dedupe, and no-op', () {
      final tags = <String>['old1', 'keep'];

      final noOp = mutateRecordTagUuids(
        tags,
        add: ['keep'],
        remove: ['missing'],
      );
      expect(noOp, isFalse);
      expect(tags, ['old1', 'keep']);

      final added = mutateRecordTagUuids(tags, add: ['keep', 'new1']);
      expect(added, isTrue);
      expect(tags, ['old1', 'keep', 'new1']);

      final rebound = mutateRecordTagUuids(
        tags,
        remove: ['old1'],
        add: ['new1', 'new2'],
      );
      expect(rebound, isTrue);
      expect(tags, ['keep', 'new1', 'new2']);
    });
  });

  group('TagBatch widgets', () {
    testWidgets('TagBatchRecordSearchField triggers onChanged and onClear', (
      tester,
    ) async {
      final controller = TextEditingController(text: '初始');
      addTearDown(controller.dispose);
      String query = '初始';
      var cleared = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TagBatchRecordSearchField(
                  controller: controller,
                  query: query,
                  hintText: '搜索记录',
                  borderRadius: 12,
                  onChanged: (v) => setState(() => query = v),
                  onClear: () {
                    cleared = true;
                    controller.clear();
                    setState(() => query = '');
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.clear), findsOneWidget);
      await tester.enterText(find.byType(TextField), '测试');
      await tester.pump();
      expect(query, '测试');

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(cleared, isTrue);
      expect(query, isEmpty);
      expect(find.byIcon(Icons.clear), findsNothing);
    });

    testWidgets('TagBatchRecordListView renders items and toggles selection', (
      tester,
    ) async {
      final selected = <String>{};
      final toggled = <(String, bool)>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TagBatchRecordListView<String>(
              items: const ['id1', 'id2'],
              idOf: (id) => id,
              selectedIds: selected,
              onToggleItem: (id, value) {
                toggled.add((id, value));
                if (value) {
                  selected.add(id);
                } else {
                  selected.remove(id);
                }
              },
              selectAllHeader: const Text('HEADER'),
              itemTitle: (id) => Text('Title $id'),
              itemSubtitle: (id) => Text('Sub $id'),
              itemTrailing: (id) => Text('Trail $id'),
            ),
          ),
        ),
      );

      expect(find.text('HEADER'), findsOneWidget);
      expect(find.text('Title id1'), findsOneWidget);
      expect(find.text('Sub id2'), findsOneWidget);
      expect(find.text('Trail id1'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(toggled, [('id1', true)]);
    });
  });
}
