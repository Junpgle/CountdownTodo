import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/historical_todos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'management_pages_test.dart' show tapVisible;

const _seriesId = '00000000-0000-4000-8000-000000000027';
final _fixedUpdatedAt = DateTime(2026, 10, 20, 20).millisecondsSinceEpoch;
const _previewFontFamily = 'Round27TrashRestorePreview';
const _previewFontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
const _fallbackFlutterRoot = '/Users/junpgle/develop/flutter';
final _iconFontPath =
    '${Platform.environment['FLUTTER_ROOT'] ?? _fallbackFlutterRoot}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
final _hasPreviewFont = Platform.isMacOS && File(_previewFontPath).existsSync();
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
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_iconFontPath).readAsBytes()),
        ),
      );
    await iconFont.load();
  }
  _previewFontsLoaded = true;
}

Future<void> _pumpRestorePage(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
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
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

List<TodoItem> _deletedSeries() => [
  TodoItem(
    id: _seriesId,
    title: '每日复习英语',
    remark: '已完成的旧期',
    updatedAt: _fixedUpdatedAt,
    recurrence: RecurrenceType.daily,
    recurrenceSeriesId: _seriesId,
    isDeleted: true,
    isDone: true,
    createdDate: DateTime.utc(2026, 10, 18, 9).millisecondsSinceEpoch,
  ),
  TodoItem(
    id: '00000000-0000-4000-8000-000000000028',
    title: '每日复习英语',
    remark: '已跳过的一期',
    updatedAt: _fixedUpdatedAt,
    recurrenceSeriesId: _seriesId,
    isDeleted: true,
    isSkipped: true,
    createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
  ),
  TodoItem(
    id: '00000000-0000-4000-8000-000000000029',
    title: '每日复习英语',
    remark: '普通未完成期',
    updatedAt: _fixedUpdatedAt,
    recurrenceSeriesId: _seriesId,
    isDeleted: true,
    createdDate: DateTime.utc(2026, 10, 20, 9).millisecondsSinceEpoch,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadPreviewFonts);

  testWidgets('整组系列折叠展示、预览状态并确认后一次恢复', (tester) async {
    final todos = _deletedSeries();
    var restoreCalls = 0;
    await _pumpRestorePage(
      tester,
      HistoricalTodosScreen(
        username: 'ui-test',
        loadTodos: () async => todos,
        loadGroups: () async => [],
        restoreRecurringSeries: (_, seriesId) async {
          expect(seriesId, _seriesId);
          restoreCalls++;
          for (final todo in todos) {
            todo.isDeleted = false;
          }
        },
      ),
    );
    await tapVisible(tester, find.text('回收站 3'));

    expect(
      find.byKey(const ValueKey('trash-series-$_seriesId')),
      findsOneWidget,
    );
    expect(find.text('每日复习英语'), findsOneWidget);
    expect(find.text('展开期次'), findsOneWidget);
    expect(find.text('恢复整组（3 期）'), findsOneWidget);
    expect(find.text('已完成的旧期'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_recurrence_trash_series_phone.png'),
    );

    await tapVisible(tester, find.text('展开期次'));
    expect(find.text('已完成的旧期'), findsOneWidget);
    expect(find.text('已跳过的一期'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/todo_recurrence_trash_series_expanded_phone.png',
      ),
    );
    await tapVisible(tester, find.text('收起期次'));
    await tapVisible(tester, find.text('恢复整组（3 期）'));
    await tester.pumpAndSettle();

    expect(find.text('恢复整组重复待办？'), findsOneWidget);
    expect(find.textContaining('全部 3 条记录'), findsOneWidget);
    expect(find.text('1 期已完成 · 1 期已跳过，状态会保留。'), findsOneWidget);
    expect(find.textContaining('原重复规则会继续生效'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/todo_recurrence_trash_series_restore_confirm_phone.png',
      ),
    );

    await tapVisible(tester, find.text('恢复整组'));
    await tester.pumpAndSettle();
    expect(restoreCalls, 1);
    expect(todos.every((todo) => !todo.isDeleted), isTrue);
    expect(todos.first.isDone, isTrue);
    expect(todos[1].isSkipped, isTrue);
    expect(todos.first.recurrence, RecurrenceType.daily);
    expect(find.text('回收站 0'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/todo_recurrence_trash_series_restored_phone.png',
      ),
    );
  });

  testWidgets('部分删除的系列仍只提供逐期恢复', (tester) async {
    final todos = [
      TodoItem(
        id: _seriesId,
        title: '每周整理资料',
        recurrence: RecurrenceType.weekly,
        recurrenceSeriesId: _seriesId,
        createdDate: DateTime.utc(2026, 10, 12, 9).millisecondsSinceEpoch,
      ),
      TodoItem(
        id: '00000000-0000-4000-8000-000000000028',
        title: '每周整理资料',
        recurrenceSeriesId: _seriesId,
        isDeleted: true,
        createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
      ),
    ];
    await _pumpRestorePage(
      tester,
      HistoricalTodosScreen(
        username: 'ui-test',
        loadTodos: () async => todos,
        loadGroups: () async => [],
        loadTodoById: (_, id) async {
          for (final todo in todos) {
            if (todo.id == id) return todo.detachedCopy();
          }
          return null;
        },
        saveTodo: (_, restored) async {
          todos[todos.indexWhere((todo) => todo.id == restored.id)] = restored;
        },
      ),
    );
    await tapVisible(tester, find.text('回收站 1'));

    expect(
      find.byKey(const ValueKey('trash-series-$_seriesId')),
      findsOneWidget,
    );
    expect(find.textContaining('恢复整组'), findsNothing);
    await tapVisible(tester, find.text('展开期次'));
    expect(find.text('恢复待办'), findsOneWidget);
  });

  testWidgets('回收站系列摘要适配手机深色大字', (tester) async {
    final todos = _deletedSeries();
    await _pumpRestorePage(
      tester,
      HistoricalTodosScreen(
        username: 'ui-test',
        loadTodos: () async => todos,
        loadGroups: () async => [],
      ),
      size: const Size(360, 800),
      scale: 1.35,
      brightness: Brightness.dark,
    );
    await tapVisible(tester, find.text('回收站 3'));
    expect(tester.takeException(), isNull);
    expect(find.text('恢复整组（3 期）'), findsOneWidget);
  });
}
