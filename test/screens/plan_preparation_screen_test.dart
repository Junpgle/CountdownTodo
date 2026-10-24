import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/screens/plan_preparation_screen.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _previewFontFamily = 'Round42PlanPreparationPreview';
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
    final font = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_iconFontPath).readAsBytes()),
        ),
      );
    await font.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadPreviewFonts);

  final now = DateTime(2026, 12, 1, 8);
  final startsAt = DateTime(2026, 12, 3, 14);
  final schedule = FixedScheduleItem(
    id: 'preparation-event',
    title: '期末考试',
    date: '2026-12-03',
    startTime: startsAt.millisecondsSinceEpoch,
    endTime: startsAt.add(const Duration(hours: 2)).millisecondsSinceEpoch,
    relatedTodoIds: const ['preparation-todo'],
  );
  final todo = TodoItem(id: 'preparation-todo', title: '复习考试范围');

  PlanPreparationScreen screen({
    String username = 'tester',
    required ValueChanged<PlanAvailabilityQuery> onQuery,
    PlanPreparationEditorOpener? openEditor,
  }) {
    return PlanPreparationScreen(
      username: username,
      schedule: schedule,
      todo: todo,
      clock: () => now,
      loadSchedule: (_, _) async =>
          FixedScheduleItem.fromJson(schedule.toJson()),
      loadTodo: (_, _) async => TodoItem.fromJson(todo.toJson()),
      loadBlocks: (_, _) async => const [],
      estimate: (_) async => const TimeEstimationResult(
        estimatedMinutes: 60,
        confidence: .2,
        reason: '历史样本较少，参考待办标题估算',
        source: TimeEstimationSource.heuristic,
        username: 'tester',
      ),
      search: (query) async {
        onQuery(query);
        final snapshot = PlanAvailabilitySnapshot(
          todo: TodoItem.fromJson(todo.toJson()),
          busy: const [],
          coverage: '已检查应用内日程和手机日历',
        );
        final slots = [
          for (var i = 0; i < 5; i++)
            PlanTimeSlot(
              DateTime(2026, 12, 1, 9 + i),
              DateTime(2026, 12, 1, 10 + i),
            ),
        ];
        return PlanContinuousRangeResult(
          query.date,
          query.date.add(const Duration(days: 7)),
          '已检查应用内日程和手机日历',
          [
            for (final slot in slots)
              PlanAvailabilitySelection(query, slot, snapshot),
          ],
          const [],
        );
      },
      revalidate: (selection) async => selection,
      openEditor: openEditor,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'tester',
      'current_user_id': 42,
    });
  });

  testWidgets(
    'shows five recommendations before event and preserves its boundary',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PlanAvailabilityQuery? query;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: _hasPreviewFont ? _previewFontFamily : null,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
          home: screen(onQuery: (value) => query = value),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('安排准备时间'), findsOneWidget);
      expect(find.text('期末考试'), findsOneWidget);
      expect(find.textContaining('只用于本次时段推荐'), findsOneWidget);
      expect(find.text('推荐时段 · 5 个'), findsOneWidget);
      expect(find.text('到时间轴拖动安排'), findsOneWidget);
      expect(query?.preparationEnd, startsAt);
      expect(query?.minutes, 60);
      expect(query?.resultLimit, 5);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../widgets/goldens/plan_preparation_phone.png'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dark narrow layout keeps duration and drag route usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
              .copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: screen(onQuery: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('preparation-duration')), findsOneWidget);
    final candidate = find.byKey(const ValueKey('preparation-candidate-0'));
    expect(candidate, findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -380));
    await tester.pumpAndSettle();
    expect(candidate.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('preparation-open-timeline')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../widgets/goldens/plan_preparation_dark_narrow.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'choosing a result passes the selected slot to the editor without saving',
    (tester) async {
      FixedSchedulePreparationContext? openedContext;
      PlanAvailabilitySelection? openedSelection;
      TodoItem? openedTodo;
      DateTime? openedStart;
      DateTime? openedEnd;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: _hasPreviewFont ? _previewFontFamily : null,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
          home: screen(
            onQuery: (_) {},
            openEditor:
                ({
                  required context,
                  required username,
                  required todo,
                  required startTime,
                  required endTime,
                  required preparationContext,
                  required preparationSelection,
                }) async {
                  openedContext = preparationContext;
                  openedSelection = preparationSelection;
                  openedTodo = todo;
                  openedStart = startTime;
                  openedEnd = endTime;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查并安排').first);
      await tester.pumpAndSettle();

      expect(openedTodo?.id, todo.id);
      expect(openedStart, DateTime(2026, 12, 1, 9));
      expect(openedEnd, DateTime(2026, 12, 1, 10));
      expect(openedContext?.scheduleId, schedule.id);
      expect(openedContext?.startTime, startsAt.millisecondsSinceEpoch);
      expect(openedSelection?.slot.start, openedStart);
      expect(openedSelection?.slot.end, openedEnd);
      expect(find.text('推荐时段 · 5 个'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
