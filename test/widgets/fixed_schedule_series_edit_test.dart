import 'dart:async';
import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/fixed_schedule_editor_screen.dart';
import 'package:countdown_todo/screens/fixed_schedule_related_todo_picker_screen.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Directory _databaseDirectory;
var _sequence = 0;
const _previewFontFamily = 'Round32FixedSchedulePreview';
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

Future<void> _pumpEditor(
  WidgetTester tester,
  String username,
  FixedScheduleItem item, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  ValueChanged<FixedScheduleItem>? onSaved,
  Future<void> Function()? rescheduleReminders,
  bool syncOnSave = false,
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
        fontFamily: _hasPreviewFont ? _previewFontFamily : null,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FixedScheduleEditorScreen(
        username: username,
        item: item,
        onSaved: onSaved,
        rescheduleReminders: rescheduleReminders ?? () async {},
        syncOnSave: syncOnSave,
        loadTeams: () async => [],
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('修改范围').evaluate().isNotEmpty ||
        find.text('只编辑当前场次').evaluate().isNotEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  expect(
    find.text('修改范围').evaluate().isNotEmpty ||
        find.text('只编辑当前场次').evaluate().isNotEmpty,
    isTrue,
  );
}

Future<(String, FixedScheduleItem)> _seedEditorData({
  bool calendarManaged = false,
}) async {
  final username = 'fixed-schedule-series-ui-${_sequence++}';
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setString('current_login_user', username);
  await prefs.setInt('current_user_id', 42);
  await prefs.setBool('migration_marker_${username}_v4', true);
  await prefs.setBool('cleanup_done_${username}_v4_repair', true);
  await prefs.setBool('conflict_detection_enabled', false);

  final series = [
    for (var index = 0; index < 3; index++)
      (() {
        final date = DateTime(2026, 10, 19 + index * 7);
        final dateText = date.toIso8601String().substring(0, 10);
        return FixedScheduleItem(
          id: 'ui-series-$index',
          title: '每周项目例会',
          date: dateText,
          startTime: DateTime(
            date.year,
            date.month,
            date.day,
            9,
          ).millisecondsSinceEpoch,
          endTime: DateTime(
            date.year,
            date.month,
            date.day,
            10,
          ).millisecondsSinceEpoch,
          recurrence: RecurrenceType.weekly,
          recurrenceSeriesId: 'ui-series-0',
          source: calendarManaged
              ? FixedScheduleSource.calendar
              : FixedScheduleSource.manual,
          externalSource: calendarManaged ? 'phone-calendar' : null,
          externalId: calendarManaged ? 'calendar-event-$index' : null,
          status: index == 0
              ? FixedScheduleStatus.finished
              : FixedScheduleStatus.scheduled,
        );
      })(),
  ];
  await StorageService.saveFixedSchedules(
    username,
    series,
    sync: false,
    isSyncSource: true,
  );
  return (username, series[1]);
}

Future<(String, FixedScheduleItem)> _seedRescheduleImpactData() async {
  final seeded = await _seedEditorData();
  final username = seeded.$1;
  final occurrence = FixedScheduleItem.fromJson(seeded.$2.toJson())
    ..relatedTodoIds = const ['1c516f9c-55ba-4db6-bc63-09a020f80001']
    ..reminderMinutes = const [15];
  await StorageService.saveFixedSchedules(
    username,
    [occurrence],
    sync: false,
    isSyncSource: true,
  );
  await StorageService.saveTodos(
    username,
    [
      TodoItem(
        id: '1c516f9c-55ba-4db6-bc63-09a020f80001',
        title: '准备面试材料',
        dueDate: DateTime(2026, 10, 28, 12),
      ),
    ],
    sync: false,
    isSyncSource: true,
  );
  await StorageService.savePlanBlocks(
    username,
    [
      TodoPlanBlock(
        id: '1c516f9c-55ba-4db6-bc63-09a020f80002',
        todoId: '1c516f9c-55ba-4db6-bc63-09a020f80003',
        titleSnapshot: '整理面试材料',
        startTime: DateTime(2026, 10, 27, 9, 30).millisecondsSinceEpoch,
        endTime: DateTime(2026, 10, 27, 10, 30).millisecondsSinceEpoch,
        status: TodoPlanStatus.planned,
      ),
    ],
    sync: false,
    isSyncSource: true,
  );
  return (username, occurrence);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadPreviewFonts();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _databaseDirectory = await Directory.systemTemp.createTemp(
      'fixed-schedule-series-ui-',
    );
    await databaseFactory.setDatabasesPath(_databaseDirectory.path);
  });

  setUp(() async {
    await DatabaseHelper.instance.closeDatabase();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await DatabaseHelper.instance.closeDatabase();
  });

  tearDownAll(() async {
    await _databaseDirectory.delete(recursive: true);
  });

  testWidgets('scope chooser and save review are clear on a phone', (
    tester,
  ) async {
    final seeded = await tester.runAsync(_seedEditorData);
    final username = seeded!.$1;
    final item = seeded.$2;
    await _pumpEditor(tester, username, item);

    await tester.tap(find.text('修改范围'));
    await tester.pumpAndSettle();
    expect(find.text('仅本次'), findsOneWidget);
    expect(find.text('本次及以后'), findsOneWidget);
    expect(find.text('整个系列'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fixed_schedule_scope_phone.png'),
    );

    await tester.tap(find.text('本次及以后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('确认本次及以后'), findsOneWidget);
    expect(find.textContaining('本次及以后形成 2 场'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fixed_schedule_future_confirm_phone.png'),
    );
  });

  testWidgets('range chooser remains readable on desktop in dark large text', (
    tester,
  ) async {
    final seeded = await tester.runAsync(_seedEditorData);
    final username = seeded!.$1;
    final item = seeded.$2;
    await _pumpEditor(
      tester,
      username,
      item,
      size: const Size(1280, 860),
      brightness: Brightness.dark,
      textScale: 1.35,
    );

    await tester.tap(find.text('修改范围'));
    await tester.pumpAndSettle();
    expect(find.text('仅本次'), findsOneWidget);
    expect(find.text('本次及以后'), findsOneWidget);
    expect(find.text('整个系列'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fixed_schedule_scope_desktop_dark_large.png'),
    );
  });

  testWidgets(
    'editor header keeps save reachable on a narrow dark large-text phone',
    (tester) async {
      final seeded = await tester.runAsync(_seedEditorData);
      await _pumpEditor(
        tester,
        seeded!.$1,
        seeded.$2,
        size: const Size(360, 800),
        brightness: Brightness.dark,
        textScale: 1.35,
      );

      final save = tester.widget<IconButton>(
        find.byKey(const ValueKey('fixed-schedule-save')),
      );
      expect(save.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/round_39_editor_header_phone_dark_large.png',
        ),
      );
    },
  );

  testWidgets('refreshes a stale route item from the current stored row', (
    tester,
  ) async {
    final seeded = await tester.runAsync(_seedEditorData);
    final username = seeded!.$1;
    final staleItem = seeded.$2;
    final latestItem = FixedScheduleItem.fromJson(staleItem.toJson())
      ..title = '最新保存的项目例会';
    latestItem.markAsChanged();
    await tester.runAsync(
      () => StorageService.saveFixedSchedules(
        username,
        [latestItem],
        sync: false,
        isSyncSource: true,
      ),
    );

    await _pumpEditor(tester, username, staleItem);
    final titleField = tester.widget<TextField>(find.byType(TextField).first);
    expect(titleField.controller!.text, '最新保存的项目例会');
  });

  testWidgets('calendar-managed recurrence stays on the current source slot', (
    tester,
  ) async {
    final seeded = await tester.runAsync(
      () => _seedEditorData(calendarManaged: true),
    );
    final username = seeded!.$1;
    final item = seeded.$2;
    await _pumpEditor(tester, username, item);

    expect(find.text('修改范围'), findsNothing);
    expect(find.text('编辑当前场次'), findsOneWidget);
    expect(find.text('只编辑当前场次'), findsOneWidget);
    expect(find.textContaining('在来源日历中修改'), findsOneWidget);
    await tester.tap(find.text('本次日期'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fixed_schedule_external_edit_phone.png'),
    );
  });

  testWidgets(
    'reschedule review shows affected data, cancel keeps storage, and confirm saves',
    (tester) async {
      final saveCompleted = Completer<FixedScheduleItem>();
      var reminderRefreshCount = 0;
      final seeded = await tester.runAsync(_seedRescheduleImpactData);
      final username = seeded!.$1;
      final occurrence = seeded.$2;
      await _pumpEditor(
        tester,
        username,
        occurrence,
        size: const Size(390, 844),
        brightness: Brightness.dark,
        onSaved: (item) {
          if (!saveCompleted.isCompleted) saveCompleted.complete(item);
        },
        rescheduleReminders: () async {
          reminderRefreshCount++;
        },
      );

      await tester.tap(find.text('修改范围'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅本次'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixed-schedule-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('27').last);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);

      Future<void> waitFor(Finder finder) async {
        for (var attempt = 0; attempt < 20; attempt++) {
          if (finder.evaluate().isNotEmpty) return;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(finder, findsOneWidget);
      }

      Future<void> openReview() async {
        await tester.tap(find.byKey(const ValueKey('fixed-schedule-save')));
        await waitFor(find.text('确认仅本次'));
        expect(find.text('确认仅本次'), findsOneWidget);
        await tester.tap(find.text('应用到仅本次'));
        await waitFor(find.text('复核改期影响'));
        expect(find.text('复核改期影响'), findsOneWidget);
      }

      await openReview();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('准备面试材料'), findsOneWidget);
      expect(find.text('整理面试材料'), findsOneWidget);
      expect(find.textContaining('保存后提醒'), findsOneWidget);
      expect(find.textContaining('截止时间晚于其中一场日程开始'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/round_39_reschedule_impact_phone_dark.png'),
      );

      await tester.tap(find.text('返回修改'));
      await tester.pumpAndSettle();
      final beforeSave = await tester.runAsync(
        () => StorageService.getFixedSchedules(username),
      );
      expect(
        beforeSave!.singleWhere((item) => item.id == occurrence.id).date,
        occurrence.date,
      );

      await openReview();
      final confirmButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-reschedule-impact')),
      );
      expect(confirmButton.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('confirm-reschedule-impact')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('fixed-schedule-reschedule-impact-dialog')),
        findsNothing,
      );
      for (var attempt = 0; attempt < 60; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (saveCompleted.isCompleted) break;
      }
      expect(
        saveCompleted.isCompleted,
        isTrue,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .whereType<String>()
            .join(' / '),
      );
      final savedItem = saveCompleted.future.then((item) => item);
      expect((await savedItem).date, '2026-10-27');
      expect(reminderRefreshCount, 1);
      await tester.pumpAndSettle();
      final afterSave = await tester.runAsync(
        () => StorageService.getFixedSchedules(username, includeDeleted: true),
      );
      expect(afterSave, isNotEmpty);
      expect(
        afterSave!.any((item) => item.date == '2026-10-27'),
        isTrue,
        reason: afterSave
            .map((item) => '${item.id}:${item.date}:${item.status.name}')
            .join(', '),
      );
      expect(
        afterSave.singleWhere((item) => item.id == occurrence.id).status,
        FixedScheduleStatus.cancelled,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('applying related todos updates the editor draft, not storage', (
    tester,
  ) async {
    final seeded = await tester.runAsync(_seedEditorData);
    final username = seeded!.$1;
    final selectedOccurrence = seeded.$2;
    await tester.runAsync(
      () => StorageService.saveTodos(
        username,
        [TodoItem(id: 'review-task', title: '复习项目内容')],
        sync: false,
        isSyncSource: true,
      ),
    );

    await _pumpEditor(tester, username, selectedOccurrence);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fixed-schedule-related-todos')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('fixed-schedule-related-todos')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('复习项目内容').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }

    expect(find.text('复习项目内容'), findsOneWidget);
    await tester.tap(find.text('复习项目内容'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('apply-related-todos')));
    await tester.pumpAndSettle();

    expect(find.textContaining('已关联 1 项'), findsOneWidget);
    final storedSeries = await tester.runAsync(
      () => StorageService.getFixedSchedules(username),
    );
    expect(
      storedSeries!
          .where((item) => item.recurrenceSeriesId == 'ui-series-0')
          .every((item) => item.relatedTodoIds.isEmpty),
      isTrue,
    );
  });

  testWidgets('a relationship read failure keeps the editor draft unsaved', (
    tester,
  ) async {
    final seeded = await tester.runAsync(_seedEditorData);
    final username = seeded!.$1;
    await tester.runAsync(
      () => StorageService.saveTodos(
        username,
        [TodoItem(id: 'review-task', title: '复习项目内容')],
        sync: false,
        isSyncSource: true,
      ),
    );

    await _pumpEditor(tester, username, seeded.$2);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fixed-schedule-related-todos')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('fixed-schedule-related-todos')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('复习项目内容').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    expect(find.text('复习项目内容'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习项目内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-related-todos')));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      await db.execute('DROP TABLE todos');
    });
    expect(find.byType(FixedScheduleRelatedTodoPickerScreen), findsNothing);
    expect(find.byType(FixedScheduleEditorScreen), findsOneWidget);
    expect(find.textContaining('已关联 1 项'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('读取关联待办失败，关系改动未保存，请重试'), findsOneWidget);
    expect(find.textContaining('已关联 1 项'), findsOneWidget);
    expect(find.text('确认整个系列'), findsNothing);
    final storedSeries = await tester.runAsync(
      () => StorageService.getFixedSchedules(username),
    );
    expect(
      storedSeries!
          .where((item) => item.recurrenceSeriesId == 'ui-series-0')
          .every((item) => item.relatedTodoIds.isEmpty),
      isTrue,
    );
  });
}
