import 'dart:async';
import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewFontFamily = 'Round38TodoFixedSchedulePreview';
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

void _setPhoneViewport(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

FixedScheduleItem _schedule(
  String id,
  String title,
  DateTime date, {
  String? teamUuid,
  String? seriesId,
  List<String> relatedTodoIds = const ['todo-a'],
  FixedScheduleStatus status = FixedScheduleStatus.scheduled,
  bool isDeleted = false,
}) => FixedScheduleItem(
  id: id,
  title: title,
  date:
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}',
  startTime: DateTime(
    date.year,
    date.month,
    date.day,
    10,
  ).millisecondsSinceEpoch,
  endTime: DateTime(date.year, date.month, date.day, 11).millisecondsSinceEpoch,
  teamUuid: teamUuid,
  recurrenceSeriesId: seriesId,
  relatedTodoIds: relatedTodoIds,
  status: status,
  isDeleted: isDeleted,
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  required TodoItem todo,
  required Future<List<FixedScheduleItem>> Function(String, String) load,
  required Future<String?> Function() username,
  Future<void> Function(String, FixedScheduleItem)? open,
  ThemeData? theme,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme:
          theme ??
          ThemeData(
            useMaterial3: true,
            fontFamily: _hasPreviewFont ? _previewFontFamily : null,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: TodoDetailScreen(
        todo: todo,
        getCurrentUsername: username,
        loadRelatedFixedSchedules: load,
        openRelatedFixedSchedule: open,
        loadFocusRecords: (_) async => const <PomodoroRecord>[],
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 3),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadPreviewFonts();
  });

  testWidgets(
    'shows a personal linked schedule, opens it, and refreshes on return',
    (tester) async {
      _setPhoneViewport(tester);
      final visible = _schedule(
        'personal-exam',
        '高等数学期末考试',
        DateTime(2099, 11, 10),
      );
      final hidden = _schedule(
        'team-exam',
        '团队私有会议',
        DateTime(2099, 11, 9),
        teamUuid: 'team-a',
      );
      var schedules = <FixedScheduleItem>[visible, hidden];
      var loads = 0;
      final opened = <String>[];

      await _pumpDetail(
        tester,
        todo: TodoItem(
          id: 'todo-a',
          title: '复习高等数学',
          createdAt: DateTime(2026, 10, 24, 9, 30).millisecondsSinceEpoch,
          createdDate: DateTime(2026, 10, 24, 9, 30).millisecondsSinceEpoch,
          updatedAt: DateTime(2026, 10, 24, 9, 30).millisecondsSinceEpoch,
        ),
        username: () async => 'account-a',
        load: (username, todoId) async {
          expect(username, 'account-a');
          expect(todoId, 'todo-a');
          loads++;
          return schedules;
        },
        open: (username, item) async {
          expect(username, 'account-a');
          opened.add(item.id);
          schedules = const [];
        },
      );

      expect(find.text('高等数学期末考试'), findsOneWidget);
      expect(find.text('团队私有会议'), findsNothing);
      await tester.ensureVisible(find.text('高等数学期末考试'));
      await _settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../widgets/goldens/todo_detail_related_fixed_schedule_single_phone.png',
        ),
      );

      await tester.tap(find.text('高等数学期末考试'));
      await _settle(tester);
      expect(opened, ['personal-exam']);
      expect(loads, greaterThanOrEqualTo(2));
      expect(find.text('暂无关联固定日程。可在固定日程编辑中关联准备待办。'), findsOneWidget);
    },
  );

  testWidgets(
    'expands a recurring series and preserves per-occurrence labels',
    (tester) async {
      _setPhoneViewport(tester);
      final previous = _schedule(
        'weekly-previous',
        '每周答辩辅导',
        DateTime(2025, 10, 17),
        seriesId: 'weekly-series',
      );
      final next = _schedule(
        'weekly-next',
        '每周答辩辅导',
        DateTime(2099, 11, 10),
        seriesId: 'weekly-series',
      );
      final cancelled = _schedule(
        'weekly-cancelled',
        '每周答辩辅导',
        DateTime(2099, 11, 17),
        seriesId: 'weekly-series',
        status: FixedScheduleStatus.cancelled,
      );
      final renamed = _schedule(
        'weekly-renamed',
        '答辩辅导（改期）',
        DateTime(2099, 11, 24),
        seriesId: 'weekly-series',
      );

      await _pumpDetail(
        tester,
        todo: TodoItem(
          id: 'todo-a',
          title: '准备答辩材料',
          createdAt: DateTime(2026, 10, 24, 9, 30).millisecondsSinceEpoch,
          createdDate: DateTime(2026, 10, 24, 9, 30).millisecondsSinceEpoch,
          updatedAt: DateTime(2026, 10, 24, 9, 30).millisecondsSinceEpoch,
        ),
        username: () async => 'account-a',
        load: (_, _) async => [previous, next, cancelled, renamed],
        open: (_, _) async {},
      );

      await tester.ensureVisible(find.text('每周答辩辅导'));
      await _settle(tester);
      expect(find.textContaining('3 场关联'), findsOneWidget);
      expect(find.text('答辩辅导（改期）'), findsOneWidget);
      await tester.tap(find.text('每周答辩辅导'));
      await _settle(tester);
      expect(find.textContaining('已取消'), findsOneWidget);
      expect(find.textContaining('未开始'), findsNWidgets(3));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../widgets/goldens/todo_detail_related_fixed_schedule_series_phone.png',
        ),
      );
    },
  );

  testWidgets('separates read failure from empty and retries', (tester) async {
    var fail = true;
    await _pumpDetail(
      tester,
      todo: TodoItem(id: 'todo-a', title: '准备考试'),
      username: () async => 'account-a',
      load: (_, _) async {
        if (fail) throw StateError('database unavailable');
        return const [];
      },
      open: (_, _) async {},
    );

    expect(find.text('关联固定日程读取失败，无法确认当前列表是否为空。'), findsOneWidget);
    expect(find.text('暂无关联固定日程。可在固定日程编辑中关联准备待办。'), findsNothing);
    fail = false;
    await tester.tap(
      find.byKey(const ValueKey('related-fixed-schedules-retry')),
    );
    await _settle(tester);
    expect(find.text('暂无关联固定日程。可在固定日程编辑中关联准备待办。'), findsOneWidget);
  });

  testWidgets('drops an old-account response and reloads the new account', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    var currentUsername = 'account-a';
    final oldLoad = Completer<List<FixedScheduleItem>>();
    final oldSchedule = _schedule(
      'private-a',
      '账号A私有考试',
      DateTime.now().add(const Duration(days: 2)),
    );
    final newSchedule = _schedule(
      'private-b',
      '账号B私有考试',
      DateTime.now().add(const Duration(days: 3)),
    );
    var firstLoad = true;

    await tester.pumpWidget(
      MaterialApp(
        home: TodoDetailScreen(
          todo: TodoItem(id: 'todo-a', title: '准备考试'),
          getCurrentUsername: () async => currentUsername,
          loadRelatedFixedSchedules: (username, _) {
            if (username == 'account-a' && firstLoad) {
              firstLoad = false;
              return oldLoad.future;
            }
            return Future.value([newSchedule]);
          },
          openRelatedFixedSchedule: (_, _) async {},
          loadFocusRecords: (_) async => const <PomodoroRecord>[],
        ),
      ),
    );
    await tester.pump();
    currentUsername = 'account-b';
    final signal = StorageService.scopedDataRefreshNotifier.value;
    StorageService.scopedDataRefreshNotifier.value = DataRefreshSignal(
      revision: signal.revision + 1,
      domains: const {DataRefreshDomain.fixedSchedules},
    );
    await _settle(tester);
    expect(find.text('账号B私有考试'), findsOneWidget);
    oldLoad.complete([oldSchedule]);
    await _settle(tester);
    expect(find.text('账号A私有考试'), findsNothing);
    expect(find.text('账号B私有考试'), findsOneWidget);
  });

  testWidgets('fits a narrow dark screen with enlarged text', (tester) async {
    _setPhoneViewport(tester, size: const Size(320, 720));
    final schedule = _schedule(
      'long-title',
      '非常长的团队年度资格认证答辩与后续材料核验会议',
      DateTime.now().add(const Duration(days: 4)),
    )..location = '合肥市高新技术开发区长江西路沿线会议中心三号楼第十二会议室';
    await _pumpDetail(
      tester,
      todo: TodoItem(id: 'todo-a', title: '整理资格认证答辩资料'),
      username: () async => 'account-a',
      load: (_, _) async => [schedule],
      open: (_, _) async {},
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      textScale: 1.4,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('related-fixed-schedule-long-title')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('非常长的团队年度资格认证答辩与后续材料核验会议'), findsOneWidget);
  });
}
