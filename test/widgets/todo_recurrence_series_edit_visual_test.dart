import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/todo_editor_save_result.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/widgets/todo_section_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

const _previewFontFamily = 'Round25CjkPreview';
const _previewFontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
const _fallbackFlutterRoot = '/Users/junpgle/develop/flutter';
final _previewIconFontPath =
    '${Platform.environment['FLUTTER_ROOT'] ?? _fallbackFlutterRoot}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
final _hasPreviewFont = Platform.isMacOS && File(_previewFontPath).existsSync();
var _previewFontLoaded = false;
var _previewIconFontLoaded = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;

  setUp(() async {
    await initializeDateFormatting();
    if (_hasPreviewFont && !_previewFontLoaded) {
      final font = FontLoader(_previewFontFamily)
        ..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(await File(_previewFontPath).readAsBytes()),
          ),
        );
      await font.load();
      _previewFontLoaded = true;
    }
    if (File(_previewIconFontPath).existsSync() && !_previewIconFontLoaded) {
      final iconFont = FontLoader('MaterialIcons')
        ..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(
              await File(_previewIconFontPath).readAsBytes(),
            ),
          ),
        );
      await iconFont.load();
      _previewIconFontLoaded = true;
    }
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    await LiquidGlassEffectService.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_coach_edit_todo', true);
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
  });

  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await fixture.dispose();
  });

  TodoItem occurrence(
    String id,
    int day, {
    bool done = false,
    bool skipped = false,
    RecurrenceType recurrence = RecurrenceType.none,
  }) => TodoItem(
    id: id,
    title: '每周整理资料',
    remark: '整理讲义并同步笔记',
    isDone: done,
    isSkipped: skipped,
    isSkippedSyncPending: skipped,
    recurrence: recurrence,
    recurrenceSeriesId: 'synthetic-series-25',
    createdDate: DateTime(2026, 10, day, 9).millisecondsSinceEpoch,
    dueDate: DateTime(2026, 10, day, 23, 59),
    isAllDay: true,
    recurrenceEndDate: DateTime(2026, 11, 30),
  );

  DateTime visualClock() => DateTime(2026, 10, 20, 12);

  Future<void> pumpEditor(
    WidgetTester tester, {
    required Size size,
    required ThemeData theme,
    required double textScale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final past = occurrence('synthetic-past', 19, done: true);
    final current = occurrence(
      'synthetic-current',
      20,
      recurrence: RecurrenceType.weekly,
    );
    final future = occurrence('synthetic-future', 22, skipped: true);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: TodoEditScreen(
            todo: current,
            todos: [past, current, future],
            todoGroups: const [],
            username: PlanAvailabilityFixture.username,
            recurrenceEditScope: TodoRecurrenceEditScope.series,
            clock: visualClock,
            onTodosChanged: (_) {},
            onEditorSave: (_, _, {expectedSeriesMembership}) async =>
                const TodoEditorSaveResult(),
            onGroupsChanged: (_) {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('窄屏系列编辑器真实界面截图', (tester) async {
    await pumpEditor(
      tester,
      size: const Size(430, 932),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff6750a4),
        useMaterial3: true,
        fontFamily: _previewFontFamily,
      ),
      textScale: 1,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('series_scope_summary')),
        matching: find.text('整个系列 · 3 期'),
      ),
      findsOneWidget,
    );
    expect(find.text('编辑系列'), findsOneWidget);
    expect(find.text('查看 3 期'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_edit_completion_switch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('series_locked_recurrence_rule')),
      findsOneWidget,
    );
    expect(find.text('关联周期'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_recurrence_series_edit_phone.png'),
    );

    await tester.tap(
      find.byKey(const ValueKey('series_occurrence_details_toggle')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('series_set_anchor_synthetic-past')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('series_set_anchor_synthetic-future')),
      findsOneWidget,
    );
    expect(find.text('当前基准'), findsOneWidget);
    await tester.tap(find.text('收起期次'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('series_set_anchor_synthetic-past')),
      findsNothing,
    );
  }, skip: !_hasPreviewFont);

  testWidgets('桌面日期偏移复核真实界面截图', (tester) async {
    await pumpEditor(
      tester,
      size: const Size(1440, 900),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff6750a4),
        useMaterial3: true,
        fontFamily: _previewFontFamily,
      ),
      textScale: 1,
    );
    expect(find.text('整个系列 · 3 期'), findsOneWidget);
    expect(find.text('编辑系列'), findsOneWidget);
    await tester.tap(find.text('完成日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('22').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用到 3 期').first);
    await tester.pumpAndSettle();
    expect(find.text('确认应用到整个系列'), findsOneWidget);
    expect(find.textContaining('日期变化基准：10月20日 这期'), findsOneWidget);
    expect(find.textContaining('10月19日 → 10月21日'), findsOneWidget);
    expect(find.textContaining('10月22日 → 10月24日'), findsOneWidget);
    expect(find.text('应用到 3 期').last, findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/todo_recurrence_series_edit_date_review_desktop.png',
      ),
    );
  }, skip: !_hasPreviewFont);

  testWidgets('深色大字系列编辑器真实界面截图', (tester) async {
    final baseDarkTheme = ThemeData.dark(useMaterial3: true);
    await pumpEditor(
      tester,
      size: const Size(430, 932),
      theme: baseDarkTheme.copyWith(
        textTheme: baseDarkTheme.textTheme.apply(
          fontFamily: _previewFontFamily,
        ),
        primaryTextTheme: baseDarkTheme.primaryTextTheme.apply(
          fontFamily: _previewFontFamily,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffb8c4ff),
          brightness: Brightness.dark,
        ),
      ),
      textScale: 1.35,
    );
    expect(find.text('整个系列 · 3 期'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/todo_recurrence_series_edit_dark_large_text.png',
      ),
    );
  }, skip: !_hasPreviewFont);

  testWidgets('重复管理菜单区分编辑范围和系列操作并保留期数信息', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final past = occurrence('menu-past', 19, done: true);
    final current = occurrence(
      'menu-current',
      20,
      recurrence: RecurrenceType.weekly,
    );
    final future = occurrence('menu-future', 22, skipped: true);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xff6750a4),
          useMaterial3: true,
          fontFamily: _previewFontFamily,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodoSectionWidget(
              todos: [past, current, future],
              username: PlanAvailabilityFixture.username,
              isLight: true,
              clock: visualClock,
              onTodosChanged: (_) {},
              onRefreshRequested: () {},
              highlightedTodoIds: const {},
              remoteUpdateHighlightSignal: 0,
              todoGroups: const [],
              conflicts: const [],
              onGroupsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final progress = find.byKey(
      const ValueKey('recurrence_progress_synthetic-series-25'),
    );
    expect(progress, findsOneWidget);
    await tester.longPress(progress);
    await tester.pumpAndSettle();

    expect(find.text('编辑范围'), findsOneWidget);
    expect(find.text('仅本期'), findsOneWidget);
    expect(find.text('本期及以后'), findsOneWidget);
    expect(find.text('整个系列'), findsOneWidget);
    expect(find.text('3 期都会修改；完成和跳过状态保留'), findsOneWidget);
    expect(find.text('系列操作'), findsOneWidget);
    expect(find.text('在本期结束重复'), findsOneWidget);
    expect(find.text('停止后续生成；本期之后已生成的关联期次移入回收站'), findsOneWidget);
    expect(find.text('移至回收站'), findsOneWidget);
    expect(find.text('按范围删除'), findsOneWidget);
    expect(find.text('当前系列共 3 期，可删除本期、后续或整个系列'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_recurrence_delete_management_phone.png'),
    );

    await tester.tap(find.text('在本期结束重复'));
    await tester.pumpAndSettle();
    expect(find.text('在本期结束重复？'), findsOneWidget);
    expect(find.textContaining('当前期和此前期次会保留'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('按范围删除'));
    await tester.pumpAndSettle();
    expect(find.text('选择「每周整理资料」的删除范围'), findsOneWidget);
    expect(find.text('仅本期 · 1期'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
