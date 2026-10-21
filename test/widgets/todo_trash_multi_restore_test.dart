import 'dart:async';
import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/historical_todos_screen.dart';
import 'package:countdown_todo/services/todo_trash_multi_restore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _seriesA = '00000000-0000-4000-8000-000000000201';
const _seriesB = '00000000-0000-4000-8000-000000000204';
const _previewFontFamily = 'Round29TrashMultiRestorePreview';
const _previewFontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
const _fallbackFlutterRoot = '/Users/junpgle/develop/flutter';
final _iconFontPath =
    '${Platform.environment['FLUTTER_ROOT'] ?? _fallbackFlutterRoot}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
final _hasPreviewFont = Platform.isMacOS && File(_previewFontPath).existsSync();
final _fixedUpdatedAt = DateTime.utc(2026, 10, 20, 12).millisecondsSinceEpoch;
var _previewFontsLoaded = false;

Future<void> _loadPreviewFonts() async {
  if (_previewFontsLoaded) return;
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
    final font = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_iconFontPath).readAsBytes()),
        ),
      );
    await font.load();
  }
  _previewFontsLoaded = true;
}

List<TodoItem> _trashTodos() => [
  TodoItem(
    id: _seriesA,
    title: '每日复习英语',
    updatedAt: _fixedUpdatedAt,
    recurrence: RecurrenceType.daily,
    recurrenceSeriesId: _seriesA,
    isDeleted: true,
    isDone: true,
    createdDate: DateTime.utc(2026, 10, 18, 9).millisecondsSinceEpoch,
  ),
  TodoItem(
    id: '00000000-0000-4000-8000-000000000202',
    title: '每日复习英语',
    updatedAt: _fixedUpdatedAt,
    recurrenceSeriesId: _seriesA,
    isDeleted: true,
    isSkipped: true,
    createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
  ),
  TodoItem(
    id: '00000000-0000-4000-8000-000000000203',
    title: '每日复习英语',
    updatedAt: _fixedUpdatedAt,
    recurrenceSeriesId: _seriesA,
    isDeleted: true,
    createdDate: DateTime.utc(2026, 10, 20, 9).millisecondsSinceEpoch,
  ),
  TodoItem(
    id: _seriesB,
    title: '每周整理笔记',
    updatedAt: _fixedUpdatedAt,
    recurrence: RecurrenceType.weekly,
    recurrenceSeriesId: _seriesB,
    isDeleted: true,
    createdDate: DateTime.utc(2026, 10, 18, 10).millisecondsSinceEpoch,
  ),
  TodoItem(
    id: '00000000-0000-4000-8000-000000000205',
    title: '每周整理笔记',
    updatedAt: _fixedUpdatedAt,
    recurrenceSeriesId: _seriesB,
    isDeleted: true,
    isSkipped: true,
    createdDate: DateTime.utc(2026, 10, 20, 10).millisecondsSinceEpoch,
  ),
  TodoItem(
    id: '00000000-0000-4000-8000-000000000206',
    title: '预约牙医',
    updatedAt: _fixedUpdatedAt,
    isDeleted: true,
    createdDate: DateTime.utc(2026, 10, 21, 11).millisecondsSinceEpoch,
  ),
];

Future<void> _pumpPage(
  WidgetTester tester,
  List<TodoItem> todos, {
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  Future<void> Function(String, TodoTrashMultiRestorePlan)? onRestore,
  Future<List<TodoItem>> Function()? loadTodos,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
        fontFamily: _hasPreviewFont ? _previewFontFamily : null,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: HistoricalTodosScreen(
        username: 'ui-test',
        loadTodos: loadTodos ?? () async => todos,
        loadGroups: () async => [],
        restoreTrashSelection: onRestore,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Tab).at(1));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadPreviewFonts);

  testWidgets('跨系列部分选择确认后只恢复所选记录', (tester) async {
    final todos = _trashTodos();
    TodoTrashMultiRestorePlan? restoredPlan;
    await _pumpPage(
      tester,
      todos,
      onRestore: (_, plan) async {
        restoredPlan = plan;
        for (final item in plan.restoredItems) {
          final index = todos.indexWhere((todo) => todo.id == item.id);
          todos[index] = item;
        }
      },
    );

    await _tap(tester, find.byTooltip('选择待办'));
    await _tap(
      tester,
      find.byKey(const ValueKey('select_trash_series_$_seriesA')),
    );
    expect(find.text('已选 3 项'), findsOneWidget);
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('trash-series-$_seriesA')),
        matching: find.text('展开期次'),
      ),
    );
    await _tap(
      tester,
      find.byKey(
        const ValueKey(
          'select_trash_todo_00000000-0000-4000-8000-000000000202',
        ),
      ),
    );
    expect(find.text('已选 2 项'), findsOneWidget);
    final partialSeriesBox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('select_trash_series_$_seriesA')),
    );
    expect(partialSeriesBox.value, isNull);

    await _tap(
      tester,
      find.byKey(const ValueKey('select_trash_series_$_seriesB')),
    );
    expect(find.text('已选 4 项'), findsOneWidget);
    final ordinarySelection = find.byKey(
      const ValueKey('select_trash_todo_00000000-0000-4000-8000-000000000206'),
    );
    await _tap(tester, ordinarySelection);
    expect(find.text('已选 5 项'), findsOneWidget);

    await _tap(
      tester,
      find.byKey(const ValueKey('restore_selected_trash_todos')),
    );
    expect(find.text('恢复选中的待办？'), findsOneWidget);
    expect(find.text('恢复 5 条待办，涉及 2 个重复系列。'), findsOneWidget);
    expect(find.text('1 条已完成 · 1 条已跳过，状态会保留。'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_trash_multi_restore_phone_confirm.png'),
    );

    await _tap(
      tester,
      find.byKey(const ValueKey('confirm_restore_selected_trash_todos')),
    );
    expect(restoredPlan?.selectedTodoIds, hasLength(5));
    expect(todos.firstWhere((todo) => todo.id == _seriesA).isDeleted, isFalse);
    expect(todos.firstWhere((todo) => todo.id == _seriesA).isDone, isTrue);
    expect(
      todos
          .firstWhere(
            (todo) => todo.id == '00000000-0000-4000-8000-000000000202',
          )
          .isDeleted,
      isTrue,
    );
    expect(
      todos
          .firstWhere(
            (todo) => todo.id == '00000000-0000-4000-8000-000000000205',
          )
          .isSkipped,
      isTrue,
    );
    expect(find.text('已恢复 5 条待办'), findsOneWidget);
    expect(find.text('已选 5 项'), findsNothing);
    expect(find.byTooltip('选择待办'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_trash_multi_restore_phone_success.png'),
    );
  });

  testWidgets('桌面深色大字选择栏与系列三态正常显示', (tester) async {
    await _pumpPage(
      tester,
      _trashTodos(),
      size: const Size(1280, 900),
      scale: 1.35,
      brightness: Brightness.dark,
    );
    await _tap(tester, find.byTooltip('选择待办'));
    await tester.tap(
      find.byKey(const ValueKey('select_trash_series_$_seriesA')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选 3 项'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/todo_trash_multi_restore_desktop_selection.png',
      ),
    );
  });

  testWidgets('切离回收站后迟到的系列读取不会恢复已取消的选择模式', (tester) async {
    final todos = _trashTodos();
    final delayedSeriesLoad = Completer<List<TodoItem>>();
    var loadCount = 0;
    await _pumpPage(
      tester,
      todos,
      loadTodos: () {
        loadCount++;
        return loadCount == 1 ? Future.value(todos) : delayedSeriesLoad.future;
      },
    );

    await _tap(tester, find.byTooltip('选择待办'));
    await tester.tap(
      find.byKey(const ValueKey('select_trash_series_$_seriesA')),
    );
    await tester.pump();
    expect(loadCount, 2);

    await tester.tap(find.byType(Tab).at(0));
    await tester.pumpAndSettle();
    delayedSeriesLoad.complete(todos);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    expect(find.byTooltip('选择待办'), findsOneWidget);
    await _tap(tester, find.byTooltip('选择待办'));
    expect(find.text('已选 3 项'), findsNothing);
    expect(find.text('已选 0 项'), findsOneWidget);
  });
}
