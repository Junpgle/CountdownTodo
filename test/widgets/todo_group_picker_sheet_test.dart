import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/widgets/todo_group_picker_sheet.dart';

void main() {
  group('TodoGroupPickerSheet', () {
    testWidgets(
      'uses centered dialog with grid on wide screens and filters by name and team name',
      (tester) async {
        // Default test surface is 800x600 (wide screen >= 600).
        final groups = List<TodoGroup>.generate(
          30,
          (i) => TodoGroup(
            id: 'g_$i',
            name: '文件夹 $i',
            teamName: i == 12 ? '研发团队' : null,
          ),
        )..add(TodoGroup(id: 'deleted_1', name: '已删除文件夹', isDeleted: true));

        TodoGroupPickerResult? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showTodoGroupPickerSheet(
                        context: context,
                        groups: groups,
                        selectedGroupId: 'g_2',
                      );
                    },
                    child: const Text('打开选择'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('打开选择'));
        await tester.pumpAndSettle();

        // Wide screen uses Dialog + GridView.
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(GridView), findsOneWidget);

        // Excluded deleted group, shows count of 30 active groups.
        expect(find.text('共 30 个'), findsOneWidget);
        expect(find.text('已删除文件夹'), findsNothing);
        expect(find.text('未分类'), findsOneWidget);

        // Search box is shown and filters by team name or folder name.
        await tester.enterText(find.byType(TextField), '研发团队');
        await tester.pumpAndSettle();

        expect(find.text('文件夹 12'), findsOneWidget);
        expect(find.text('文件夹 0'), findsNothing);

        // Empty state + clear button when nothing matches.
        await tester.enterText(find.byType(TextField), '不存在的目录');
        await tester.pumpAndSettle();

        expect(find.text('没有找到匹配的文件夹'), findsOneWidget);
        await tester.tap(find.text('清空搜索'));
        await tester.pumpAndSettle();

        expect(find.text('未分类'), findsOneWidget);

        // Filter to folder 12 and tap it.
        await tester.enterText(find.byType(TextField), '文件夹 12');
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(GridView),
            matching: find.text('文件夹 12'),
          ),
        );
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.groupId, 'g_12');
      },
    );

    testWidgets(
      'uses bottom sheet with list on compact screens and returns uncategorized',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final groups = [
          TodoGroup(id: 'g_1', name: '工作'),
          TodoGroup(id: 'g_2', name: '生活'),
        ];

        TodoGroupPickerResult? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showTodoGroupPickerSheet(
                        context: context,
                        groups: groups,
                        selectedGroupId: 'g_1',
                      );
                    },
                    child: const Text('打开选择'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('打开选择'));
        await tester.pumpAndSettle();

        // Compact screen uses bottom sheet + ListView, not Dialog.
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(ListView), findsOneWidget);

        // Search box hidden for small folder counts (< 5).
        expect(find.byType(TextField), findsNothing);

        await tester.tap(find.text('未分类'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.groupId, isNull);
      },
    );
  });
}
