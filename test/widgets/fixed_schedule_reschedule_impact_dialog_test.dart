import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/fixed_schedule_reschedule_impact_service.dart';
import 'package:countdown_todo/widgets/fixed_schedule_reschedule_impact_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewFontFamily = 'Round39ImpactPreview';
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

DateTime _local(String date, int hour, [int minute = 0]) => DateTime.parse(
  '${date}T${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00',
);

FixedScheduleRescheduleImpact _impact() {
  const todoId = '1c516f9c-55ba-4db6-bc63-09a020f80011';
  final before = FixedScheduleItem(
    id: 'impact-old-schedule',
    title: '期末考试',
    date: '2026-11-19',
    startTime: _local('2026-11-19', 9).millisecondsSinceEpoch,
    endTime: _local('2026-11-19', 10).millisecondsSinceEpoch,
    relatedTodoIds: const [todoId],
    reminderMinutes: const [15],
  );
  final after = FixedScheduleItem(
    id: 'impact-new-schedule',
    title: '期末考试',
    date: '2026-11-20',
    startTime: _local('2026-11-20', 9).millisecondsSinceEpoch,
    endTime: _local('2026-11-20', 10).millisecondsSinceEpoch,
    relatedTodoIds: const [todoId],
    reminderMinutes: const [15],
  );
  final cancelledBefore = FixedScheduleItem.fromJson(before.toJson())
    ..status = FixedScheduleStatus.cancelled;
  final todo = TodoItem(
    id: todoId,
    title: '整理考试材料',
    dueDate: _local('2026-11-21', 12),
  );
  final plan = TodoPlanBlock(
    id: '1c516f9c-55ba-4db6-bc63-09a020f80012',
    todoId: '1c516f9c-55ba-4db6-bc63-09a020f80013',
    titleSnapshot: '最后一轮复习',
    startTime: _local('2026-11-20', 9, 30).millisecondsSinceEpoch,
    endTime: _local('2026-11-20', 10, 30).millisecondsSinceEpoch,
  );
  return FixedScheduleRescheduleImpactService.build(
    baseline: [before],
    active: [after],
    changes: [cancelledBefore, after],
    scope: FixedScheduleEditScope.occurrence,
    selectedOccurrence: before,
    refreshItem: after,
    todos: [todo],
    planBlocks: [plan],
    now: _local('2026-10-24', 9),
  );
}

void main() {
  setUpAll(_loadPreviewFonts);

  testWidgets(
    'review dialog remains readable on a narrow dark large-text phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final impact = _impact();
      FixedScheduleRescheduleImpact? accepted;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: _hasPreviewFont ? _previewFontFamily : null,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.35)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    accepted = await showDialog<FixedScheduleRescheduleImpact>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => FixedScheduleRescheduleImpactDialog(
                        impact: impact,
                        reload: () async => impact,
                        openTodo: (_) async {},
                        openPlan: (_) async {},
                      ),
                    );
                  },
                  child: const Text('打开复核'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开复核'));
      await tester.pumpAndSettle();

      expect(find.text('复核改期影响'), findsOneWidget);
      expect(find.text('期末考试'), findsOneWidget);
      expect(find.text('整理考试材料'), findsOneWidget);
      expect(find.text('最后一轮复习'), findsOneWidget);
      expect(find.textContaining('截止时间晚于其中一场日程开始'), findsOneWidget);
      expect(find.textContaining('提前15分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/round_39_reschedule_impact_narrow_dark_large.png',
        ),
      );

      await tester.tap(find.byKey(const ValueKey('confirm-reschedule-impact')));
      await tester.pumpAndSettle();
      expect(accepted?.snapshotSignature, impact.snapshotSignature);
      expect(tester.takeException(), isNull);
    },
  );
}
