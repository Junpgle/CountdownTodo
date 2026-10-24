import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/fixed_schedule_related_todo_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewFontFamily = 'Round37FixedSchedulePickerPreview';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadPreviewFonts);

  final todos = [
    TodoItem(
      id: 'review-exam',
      title: '复习考试范围',
      dueDate: DateTime(2026, 11, 2, 20),
    ),
    TodoItem(
      id: 'print-admission',
      title: '打印准考证',
      isDone: true,
      dueDate: DateTime(2026, 11, 1),
    ),
  ];

  String? normalizeTeam(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  FixedScheduleRelatedTodoPageLoader pageLoaderFor(List<TodoItem> source) =>
      (
        String _, {
        required String? teamUuid,
        required String query,
        required int limit,
        required int offset,
      }) async {
        final normalizedQuery = query.trim().toLowerCase();
        final normalizedTeamUuid = normalizeTeam(teamUuid);
        final filtered =
            source.where((todo) {
              final sameTeam =
                  normalizeTeam(todo.teamUuid) == normalizedTeamUuid;
              final status = todo.isDone
                  ? '已完成'
                  : todo.isSkipped
                  ? '已跳过'
                  : '待完成';
              return !todo.isDeleted &&
                  sameTeam &&
                  (normalizedQuery.isEmpty ||
                      todo.title.toLowerCase().contains(normalizedQuery) ||
                      status.contains(normalizedQuery));
            }).toList()..sort((left, right) {
              int statusOrder(TodoItem todo) =>
                  todo.isDone || todo.isSkipped ? 1 : 0;

              final statusCompare = statusOrder(left)
                  .compareTo(statusOrder(right));
              if (statusCompare != 0) return statusCompare;
              final leftDue = left.dueDate?.millisecondsSinceEpoch;
              final rightDue = right.dueDate?.millisecondsSinceEpoch;
              if (leftDue == null && rightDue != null) return 1;
              if (leftDue != null && rightDue == null) return -1;
              if (leftDue != null && rightDue != null && leftDue != rightDue) {
                return leftDue.compareTo(rightDue);
              }
              return left.title.toLowerCase().compareTo(
                right.title.toLowerCase(),
              );
            });
        final page = filtered.skip(offset).take(limit).toList();
        return (todos: page, hasMore: offset + page.length < filtered.length);
      };

  FixedScheduleRelatedTodoIdsLoader selectedLoaderFor(List<TodoItem> source) =>
      (String _, Set<String> ids) async =>
          source.where((todo) => ids.contains(todo.id)).toList();

  testWidgets('选择页修改先隔离，取消丢弃，应用才返回新集合', (tester) async {
    Set<String>? result;
    var returned = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<Set<String>>(
                  MaterialPageRoute(
                    builder: (_) => FixedScheduleRelatedTodoPickerScreen(
                      username: 'tester',
                      teamUuid: null,
                      initialSelectedIds: const {},
                      loadTodoPage: pageLoaderFor(todos),
                      loadSelectedTodos: selectedLoaderFor(todos),
                    ),
                  ),
                );
                returned = true;
              },
              child: const Text('打开选择'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开选择'));
    await tester.pumpAndSettle();
    expect(find.text('复习考试范围'), findsOneWidget);
    expect(find.text('打印准考证'), findsOneWidget);
    expect(find.textContaining('已完成'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '打印');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('复习考试范围'), findsNothing);
    expect(find.text('打印准考证'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打印准考证'));
    await tester.pumpAndSettle();
    expect(find.text('应用 1 项'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNull);

    returned = false;
    await tester.tap(find.text('打开选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习考试范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-related-todos')));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, {'review-exam'});
  });

  testWidgets('团队日程只显示同团队待办，并允许关联已完成事项', (tester) async {
    final teamTodos = [
      TodoItem(id: 'team-task', title: '团队准备任务', teamUuid: 'team-a'),
      TodoItem(id: 'private-task', title: '个人私有任务'),
      TodoItem(
        id: 'team-done',
        title: '团队材料已办完',
        isDone: true,
        teamUuid: 'team-a',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleRelatedTodoPickerScreen(
          username: 'tester',
          teamUuid: 'team-a',
          initialSelectedIds: const {},
          loadTodoPage: pageLoaderFor(teamTodos),
          loadSelectedTodos: selectedLoaderFor(teamTodos),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('团队准备任务'), findsOneWidget);
    expect(find.text('团队材料已办完'), findsOneWidget);
    expect(find.text('个人私有任务'), findsNothing);
  });

  testWidgets('窄屏深色大字下仍可搜索并应用', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: FixedScheduleRelatedTodoPickerScreen(
          username: 'tester',
          teamUuid: null,
          initialSelectedIds: const {'review-exam'},
          loadTodoPage: pageLoaderFor(todos),
          loadSelectedTodos: selectedLoaderFor(todos),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关联待办'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('应用 1 项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone picker screenshot', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: _hasPreviewFont ? _previewFontFamily : null,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: FixedScheduleRelatedTodoPickerScreen(
          username: 'tester',
          teamUuid: null,
          initialSelectedIds: const {'review-exam'},
          loadTodoPage: pageLoaderFor(todos),
          loadSelectedTodos: selectedLoaderFor(todos),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../widgets/goldens/fixed_schedule_related_picker_phone.png',
      ),
    );
  });
}
