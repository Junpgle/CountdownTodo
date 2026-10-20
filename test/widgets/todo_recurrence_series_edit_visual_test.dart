import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/todo_editor_save_result.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
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
final _hasPreviewFont = Platform.isMacOS && File(_previewFontPath).existsSync();
var _previewFontLoaded = false;

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
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    await LiquidGlassEffectService.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_coach_edit_todo', true);
  });

  tearDown(() async => fixture.dispose());

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
    expect(find.textContaining('整个系列 · 3 期'), findsOneWidget);
    expect(find.text('整系列编辑保留每期状态'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/todo_recurrence_series_edit_phone.png'),
    );
  }, skip: !_hasPreviewFont);

  testWidgets('桌面日期偏移复核真实界面截图', (tester) async {
    await pumpEditor(
      tester,
      size: const Size(1440, 1000),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff6750a4),
        useMaterial3: true,
        fontFamily: _previewFontFamily,
      ),
      textScale: 1,
    );
    expect(find.textContaining('整个系列 · 3 期'), findsOneWidget);
    await tester.tap(find.text('完成日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('22').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();
    expect(find.text('确认应用到整个系列'), findsOneWidget);
    expect(find.textContaining('日期或时间会按当前期的偏移同步到所有期次。'), findsOneWidget);
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
    expect(find.textContaining('整个系列 · 3 期'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/todo_recurrence_series_edit_dark_large_text.png',
      ),
    );
  }, skip: !_hasPreviewFont);
}
