import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/todo_create_save_result.dart';
import 'package:countdown_todo/screens/add_todo_screen.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/screens/fixed_schedule_detail_screen.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _setPhoneViewport(tester);
    final item = FixedScheduleItem(
      title: '考试',
      date: '2026-12-04',
      startTime: DateTime(2026, 12, 4, 9, 15).millisecondsSinceEpoch,
      endTime: DateTime(2026, 12, 4, 10, 45).millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: _hasPreviewFont ? _previewFontFamily : null,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: FixedScheduleDetailScreen(
          username: 'tester',
          item: item,
          onCreateRelatedTodo: (todo, baseline) async =>
              FixedScheduleTodoSaveResult(schedule: baseline),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年12月4日 · 09:15 - 10:45'), findsOneWidget);
    expect(find.text('暂无关联待办，可以关联已有待办。'), findsOneWidget);
    expect(find.text('2026年12月4日'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
    expect(find.text('10:45'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../widgets/goldens/fixed_schedule_empty_detail_phone.png',
      ),
    );
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
          loadRelatedFixedSchedules: (_, _) async => [item],
          getCurrentUsername: () async => 'tester',
          loadTodoFocusRecords: (_) async => const <PomodoroRecord>[],
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
    expect(find.text('高等数学考试'), findsOneWidget);

    isDone = true;
    Navigator.of(tester.element(find.byType(TodoDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('已完成 · 2026年12月3日 20:00'), findsOneWidget);
  });

  testWidgets('已有关联待办时仍可新建准备待办', (tester) async {
    final item = FixedScheduleItem(
      id: 'exam-with-todo',
      title: '期末考试',
      date: '2026-12-04',
      relatedTodoIds: const ['existing-prep'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleDetailScreen(
          username: 'tester',
          item: item,
          loadRelatedTodos: (_) async => [
            TodoItem(id: 'existing-prep', title: '整理笔记'),
          ],
          onCreateRelatedTodo: (todo, baseline) async =>
              FixedScheduleTodoSaveResult(schedule: baseline),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关联待办 · 1'), findsOneWidget);
    expect(find.text('整理笔记'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fixed-schedule-create-related-todo')),
      findsOneWidget,
    );
  });

  testWidgets('已取消场次不显示新建关联待办入口', (tester) async {
    final item = FixedScheduleItem(
      id: 'cancelled-schedule',
      title: '已取消的面试',
      date: '2026-12-04',
      status: FixedScheduleStatus.cancelled,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleDetailScreen(
          username: 'tester',
          item: item,
          onCreateRelatedTodo: (todo, baseline) async =>
              FixedScheduleTodoSaveResult(schedule: baseline),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('fixed-schedule-create-related-todo')),
      findsNothing,
    );
    expect(find.text('关联已有待办'), findsOneWidget);
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
    expect(find.text('暂无关联待办，可以关联已有待办。'), findsNothing);
  });

  testWidgets('从当前日程新建准备待办并只关联当前场次', (tester) async {
    _setPhoneViewport(tester);
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'tester',
      'current_user_id': 42,
      'tip_shown_coach_add_todo': true,
    });
    final item = FixedScheduleItem(
      id: 'one-occurrence',
      title: '实验室面试',
      date: '2026-12-04',
      startTime: DateTime(2026, 12, 4, 9, 15).millisecondsSinceEpoch,
      endTime: DateTime(2026, 12, 4, 10, 45).millisecondsSinceEpoch,
      teamUuid: 'team-a',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'interview-series',
    );
    final createdTodos = <TodoItem>[];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: _hasPreviewFont ? _previewFontFamily : null,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: FixedScheduleDetailScreen(
          username: 'tester',
          item: item,
          loadRelatedTodos: (_) async => createdTodos,
          onCreateRelatedTodo: (todo, baseline) async {
            createdTodos.add(todo);
            final updated = FixedScheduleItem.fromJson(baseline.toJson())
              ..relatedTodoIds.add(todo.id)
              ..markAsChanged();
            return FixedScheduleTodoSaveResult(schedule: updated);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final createButton = find.byKey(
      const ValueKey('fixed-schedule-create-related-todo'),
    );
    final detailScroll = find.byType(Scrollable).first;
    for (
      var attempt = 0;
      attempt < 8 && createButton.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(detailScroll, const Offset(0, -420));
      await tester.pumpAndSettle();
    }
    expect(createButton, findsOneWidget);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.byType(AddTodoScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('related-fixed-schedule-context')),
      findsOneWidget,
    );
    expect(find.text('实验室面试'), findsOneWidget);
    expect(find.text('2026年12月4日 · 09:15 - 10:45'), findsOneWidget);
    expect(find.text('仅关联当前场次'), findsOneWidget);
    expect(find.text('重复规则'), findsNothing);
    expect(find.text('与固定日程保持一致'), findsOneWidget);
    final teamTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('团队归属'), matching: find.byType(ListTile)),
    );
    expect(teamTile.onTap, isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('manual-todo-title')))
          .controller!
          .text,
      isEmpty,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../widgets/goldens/fixed_schedule_create_related_todo_phone.png',
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('manual-todo-title')),
      '整理面试材料',
    );
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(createdTodos, hasLength(1));
    expect(createdTodos.single.title, '整理面试材料');
    expect(createdTodos.single.teamUuid, 'team-a');
    expect(createdTodos.single.recurrence, RecurrenceType.none);
    expect(createdTodos.single.dueDate, isNull);
    expect(find.text('整理面试材料'), findsOneWidget);
    expect(find.text('关联待办 · 1'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 1200);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../widgets/goldens/fixed_schedule_linked_after_create_phone.png',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('关联新建的退出保护保留输入，放弃草稿不调用保存', (tester) async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'tester',
      'current_user_id': 42,
      'tip_shown_coach_add_todo': true,
    });
    final item = FixedScheduleItem(
      id: 'exit-protection-schedule',
      title: '准备面试',
      date: '2026-12-04',
    );
    var saveCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: FixedScheduleDetailScreen(
          username: 'tester',
          item: item,
          onCreateRelatedTodo: (todo, baseline) async {
            saveCalls++;
            return FixedScheduleTodoSaveResult(schedule: baseline);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final createButton = find.byKey(
      const ValueKey('fixed-schedule-create-related-todo'),
    );
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('manual-todo-title')),
      '准备项目介绍',
    );
    await tester.pump();

    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop<void>();
    await tester.pumpAndSettle();
    expect(find.text('内容还没有保存'), findsOneWidget);
    await tester.tap(find.text('继续填写'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('manual-todo-title')))
          .controller!
          .text,
      '准备项目介绍',
    );
    expect(saveCalls, 0);

    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop<void>();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃草稿'));
    await tester.pumpAndSettle();

    expect(find.byType(AddTodoScreen), findsNothing);
    expect(saveCalls, 0);
  });

  testWidgets('关联待办上下文在深色大字窄屏仍可滚动访问', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'tester',
      'current_user_id': 42,
      'tip_shown_coach_add_todo': true,
    });
    final item = FixedScheduleItem(
      id: 'narrow-preview-schedule',
      title: '深色大字窄屏面试准备',
      date: '2026-12-04',
      teamUuid: 'team-a',
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: _hasPreviewFont ? _previewFontFamily : null,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: FixedScheduleDetailScreen(
          username: 'tester',
          item: item,
          onCreateRelatedTodo: (todo, baseline) async =>
              FixedScheduleTodoSaveResult(schedule: baseline),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final createButton = find.byKey(
      const ValueKey('fixed-schedule-create-related-todo'),
    );
    final detailScroll = find.byType(Scrollable).first;
    for (
      var attempt = 0;
      attempt < 8 && createButton.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(detailScroll, const Offset(0, -420));
      await tester.pumpAndSettle();
    }
    expect(createButton, findsOneWidget);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.byType(AddTodoScreen), findsOneWidget);
    expect(find.text('仅关联当前场次'), findsOneWidget);
    expect(find.text('新建待办'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../widgets/goldens/fixed_schedule_create_related_todo_narrow_dark_large.png',
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('manual-todo-title')));
    await tester.ensureVisible(find.text('与固定日程保持一致'));
    expect(find.text('与固定日程保持一致'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
