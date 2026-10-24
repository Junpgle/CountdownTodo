import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/screens/fixed_schedule_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewFontFamily = 'Round37FixedScheduleDetailPreview';
const _previewFontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
const _fallbackFlutterRoot = '/Users/junpgle/develop/flutter';
final _iconFontPath =
    '${Platform.environment['FLUTTER_ROOT'] ?? _fallbackFlutterRoot}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
final _hasPreviewFont = Platform.isMacOS && File(_previewFontPath).existsSync();

Future<void> _loadPreviewFonts() async {
  if (_hasPreviewFont) {
    final font = FontLoader(_previewFontFamily)
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_previewFontPath).readAsBytes()),
        ),
      );
    await font.load();
  }
  if (File(_iconFontPath).existsSync()) {
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_iconFontPath).readAsBytes()),
        ),
      );
    await iconFont.load();
  }
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadPreviewFonts);

  testWidgets('shows the date and known fixed schedule times', (tester) async {
    final item = FixedScheduleItem(
      title: '考试',
      date: '2026-12-04',
      startTime: DateTime(2026, 12, 4, 9, 15).millisecondsSinceEpoch,
      endTime: DateTime(2026, 12, 4, 10, 45).millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleDetailScreen(username: 'tester', item: item),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年12月4日 · 09:15 - 10:45'), findsOneWidget);
    expect(find.text('暂无关联待办，可在编辑固定日程时添加准备事项。'), findsOneWidget);
    expect(find.text('2026年12月4日'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
    expect(find.text('10:45'), findsOneWidget);
  });

  testWidgets('preserves the time-undetermined labels', (tester) async {
    final item = FixedScheduleItem(title: '待定日程', date: '2026-12-04');

    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleDetailScreen(username: 'tester', item: item),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年12月4日 · 时间待定'), findsOneWidget);
    expect(find.text('待定'), findsNWidgets(2));
  });

  testWidgets('shows linked todo status and date, then opens its detail', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final item = FixedScheduleItem(
      id: 'exam',
      title: '高等数学考试',
      date: '2026-12-04',
      startTime: DateTime(2026, 12, 4, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 12, 4, 11).millisecondsSinceEpoch,
      relatedTodoIds: const ['review-exam'],
    );
    var isDone = false;

    Future<List<TodoItem>> loadRelatedTodos(String _) async => [
      TodoItem(
        id: 'review-exam',
        title: '复习考试范围',
        isDone: isDone,
        dueDate: DateTime(2026, 12, 3, 20),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: _hasPreviewFont ? _previewFontFamily : null,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: FixedScheduleDetailScreen(
          username: 'tester',
          item: item,
          loadRelatedTodos: loadRelatedTodos,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关联待办 · 1'), findsOneWidget);
    expect(find.text('复习考试范围'), findsOneWidget);
    expect(find.text('待完成 · 2026年12月3日 20:00'), findsOneWidget);

    await tester.ensureVisible(find.text('复习考试范围'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../widgets/goldens/fixed_schedule_related_detail_phone.png',
      ),
    );

    await tester.tap(find.text('复习考试范围'));
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(find.text('复习考试范围'), findsOneWidget);

    isDone = true;
    Navigator.of(tester.element(find.byType(TodoDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('已完成 · 2026年12月3日 20:00'), findsOneWidget);
  });

  testWidgets(
    'missing and invisible links remain explicit without exposing titles',
    (tester) async {
      final item = FixedScheduleItem(
        id: 'team-exam',
        title: '团队考试',
        date: '2026-12-04',
        teamUuid: 'team-a',
        relatedTodoIds: const ['missing-todo', 'private-todo', 'deleted-todo'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FixedScheduleDetailScreen(
            username: 'tester',
            item: item,
            loadRelatedTodos: (_) async => [
              TodoItem(id: 'private-todo', title: '个人私密任务'),
              TodoItem(
                id: 'deleted-todo',
                title: '已删除的团队事项',
                teamUuid: 'team-a',
                isDeleted: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('关联待办不可用'), findsNWidgets(3));
      expect(find.text('个人私密任务'), findsNothing);
      expect(find.text('已删除的团队事项'), findsNothing);
      expect(find.text('已删除'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read failure is distinct from an empty relationship list', (
    tester,
  ) async {
    final item = FixedScheduleItem(
      id: 'exam',
      title: '考试',
      date: '2026-12-04',
      relatedTodoIds: const ['missing-todo'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleDetailScreen(
          username: 'tester',
          item: item,
          loadRelatedTodos: (_) async =>
              throw StateError('database unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关联待办读取失败，不能确认当前列表是否为空。'), findsOneWidget);
    expect(find.text('暂无关联待办，可在编辑固定日程时添加准备事项。'), findsNothing);
  });
}
