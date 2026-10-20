import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/historical_todos_screen.dart';
import 'package:countdown_todo/services/todo_trash_purge_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'management_pages_test.dart' show tapVisible;

const _seriesId = '00000000-0000-4000-8000-000000000071';
const _previewFontFamily = 'Round28TrashPurgePreview';
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

TodoItem _todo(
  String id,
  String title, {
  String? seriesId,
  bool deleted = false,
  bool done = false,
  bool skipped = false,
  DateTime? date,
  RecurrenceType recurrence = RecurrenceType.none,
}) => TodoItem(
  id: id,
  title: title,
  recurrence: recurrence,
  recurrenceSeriesId: seriesId,
  isDeleted: deleted,
  isDone: done,
  isSkipped: skipped,
  createdDate: (date ?? DateTime.utc(2026, 10, 20, 9)).millisecondsSinceEpoch,
  updatedAt: DateTime.utc(2026, 10, 20, 12).millisecondsSinceEpoch,
);

List<TodoItem> _partialSeries() => [
  _todo(
    _seriesId,
    '每日复习英语',
    seriesId: _seriesId,
    recurrence: RecurrenceType.daily,
    date: DateTime.utc(2026, 10, 20, 9),
  ),
  _todo(
    '00000000-0000-4000-8000-000000000072',
    '每日复习英语',
    seriesId: _seriesId,
    deleted: true,
    done: true,
    date: DateTime.utc(2026, 10, 18, 9),
  ),
  _todo(
    '00000000-0000-4000-8000-000000000073',
    '每日复习英语',
    seriesId: _seriesId,
    deleted: true,
    skipped: true,
    date: DateTime.utc(2026, 10, 19, 9),
  ),
];

Future<void> _pumpPage(
  WidgetTester tester,
  List<TodoItem> todos, {
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
        useMaterial3: true,
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
        username: 'trash-purge-ui',
        loadTodos: () async => List.of(todos),
        loadGroups: () async => [],
        previewTrashItemPurge: (_, uuid) async => TodoTrashPurgeService.forItem(
          todos.singleWhere((todo) => todo.id == uuid),
        ),
        previewTrashSeriesPurge: (_, seriesId) async =>
            TodoTrashPurgeService.forSeries(todos, seriesId),
        previewTrashClear: (_) async =>
            TodoTrashPurgeService.forRecycleBin(todos),
        purgeTrash: (_, plan) async {
          todos.removeWhere((todo) => plan.targetIds.contains(todo.id));
          return TodoTrashPurgeResult(
            deletedCount: plan.targetEntries.length,
            cacheCleared: true,
            conflictsRefreshed: true,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openRecycleBin(WidgetTester tester, int count) async {
  await tapVisible(tester, find.text('回收站 $count'));
  await tester.pumpAndSettle();
}

Future<void> _openSeriesPurge(WidgetTester tester) async {
  await tapVisible(
    tester,
    find.byKey(ValueKey('trash_series_more_$_seriesId')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('清理该系列回收站记录'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadPreviewFonts);

  testWidgets('部分删除系列显示精确范围，取消不执行清理', (tester) async {
    final todos = _partialSeries();
    await _pumpPage(tester, todos);
    await _openRecycleBin(tester, 2);
    await _openSeriesPurge(tester);

    expect(find.text('清理该系列回收站记录？'), findsOneWidget);
    expect(find.textContaining('将永久删除 2 条待办，覆盖 2 期。'), findsOneWidget);
    expect(find.text('只清理回收站中的期次；活动期次和重复规则会保留。'), findsOneWidget);
    expect(find.text('1 期已完成 · 1 期已跳过。'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_trash_purge_partial_confirm_phone.png'),
    );

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(todos.where((todo) => todo.isDeleted), hasLength(2));
    expect(find.text('回收站 2'), findsOneWidget);
  });

  testWidgets('完整删除系列确认明确覆盖全部现存记录', (tester) async {
    final todos = [
      _todo(
        _seriesId,
        '每周整理资料',
        seriesId: _seriesId,
        deleted: true,
        date: DateTime.utc(2026, 10, 13, 9),
      ),
      _todo(
        '00000000-0000-4000-8000-000000000074',
        '每周整理资料',
        seriesId: _seriesId,
        deleted: true,
        date: DateTime.utc(2026, 10, 20, 9),
      ),
    ];
    await _pumpPage(tester, todos);
    await _openRecycleBin(tester, 2);
    await _openSeriesPurge(tester);

    expect(find.text('删除该系列全部现存记录？'), findsOneWidget);
    expect(find.text('该系列当前所有现存期次均在回收站，将全部删除。'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_trash_purge_full_confirm_phone.png'),
    );
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(find.text('回收站 0'), findsOneWidget);
    expect(find.text('已清理该系列 2 条回收站记录'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_trash_purge_series_success_phone.png'),
    );
  });

  testWidgets('清空回收站预览展示精确数量并说明不受搜索影响', (tester) async {
    final todos = [
      _todo(
        'trash-clear-ui-1',
        '已完成内容',
        deleted: true,
        done: true,
        date: DateTime.utc(2026, 10, 18, 9),
      ),
      _todo(
        'trash-clear-ui-2',
        '搜索隐藏内容',
        deleted: true,
        skipped: true,
        date: DateTime.utc(2026, 10, 19, 9),
      ),
      _todo(
        'trash-clear-ui-3',
        '更多内容',
        deleted: true,
        date: DateTime.utc(2026, 10, 20, 9),
      ),
    ];
    await _pumpPage(tester, todos, size: const Size(1280, 850));
    await _openRecycleBin(tester, 3);
    await tapVisible(tester, find.text('清空全部'));
    await tester.pumpAndSettle();

    expect(find.text('清空全部回收站？'), findsOneWidget);
    expect(find.textContaining('将永久删除 3 条待办，覆盖 3 期。'), findsOneWidget);
    expect(find.text('范围为整个回收站，包括搜索隐藏和未加载的待办。'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_trash_purge_clear_confirm_desktop.png'),
    );
  });

  testWidgets('窄屏深色大字体的系列确认无布局异常', (tester) async {
    final todos = _partialSeries();
    await _pumpPage(
      tester,
      todos,
      size: const Size(360, 800),
      scale: 1.35,
      brightness: Brightness.dark,
    );
    await _openRecycleBin(tester, 2);
    await _openSeriesPurge(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
