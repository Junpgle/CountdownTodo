import 'package:countdown_todo/screens/time_log_save_confirmation.dart';
import 'package:countdown_todo/services/time_log_overlap_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows overlap details and returns false when user goes back', (
    tester,
  ) async {
    Future<bool?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                result = showTimeLogSaveConfirmation(
                  context: context,
                  start: DateTime(2026, 10, 19, 10),
                  end: DateTime(2026, 10, 19, 10, 30),
                  overlaps: [
                    TimeLogOverlap(
                      source: TimeLogOverlapSource.pomodoro,
                      id: 'pom-1',
                      title: '复习英语',
                      startTime: DateTime(
                        2026,
                        10,
                        19,
                        10,
                        5,
                      ).millisecondsSinceEpoch,
                      endTime: DateTime(
                        2026,
                        10,
                        19,
                        10,
                        25,
                      ).millisecondsSinceEpoch,
                      overlapMilliseconds: const Duration(minutes: 20)
                          .inMilliseconds,
                    ),
                  ],
                  isFuture: true,
                  isEditing: false,
                );
              },
              child: const Text('打开确认'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();

    expect(find.text('发现时间重叠'), findsOneWidget);
    expect(find.text('复习英语'), findsOneWidget);
    expect(find.text('番茄钟'), findsOneWidget);
    expect(find.text('20 分钟'), findsOneWidget);
    expect(find.textContaining('结束时间晚于当前时间'), findsOneWidget);
    expect(find.text('仍然保存'), findsOneWidget);

    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('returns true when user explicitly saves despite overlaps', (
    tester,
  ) async {
    Future<bool?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                result = showTimeLogSaveConfirmation(
                  context: context,
                  start: DateTime(2026, 10, 19, 10),
                  end: DateTime(2026, 10, 19, 10, 30),
                  overlaps: [
                    TimeLogOverlap(
                      source: TimeLogOverlapSource.manualLog,
                      id: 'log-1',
                      title: '已有补录',
                      startTime: DateTime(
                        2026,
                        10,
                        19,
                        10,
                      ).millisecondsSinceEpoch,
                      endTime: DateTime(
                        2026,
                        10,
                        19,
                        10,
                        10,
                      ).millisecondsSinceEpoch,
                      overlapMilliseconds: const Duration(minutes: 10)
                          .inMilliseconds,
                    ),
                  ],
                  isFuture: false,
                  isEditing: true,
                );
              },
              child: const Text('打开确认'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仍然保存'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });

  testWidgets('limits long overlap lists and explains how many remain', (
    tester,
  ) async {
    final overlaps = List.generate(
      6,
      (index) => TimeLogOverlap(
        source: TimeLogOverlapSource.manualLog,
        id: 'log-$index',
        title: '记录 $index',
        startTime: DateTime(2026, 10, 19, 10, index).millisecondsSinceEpoch,
        endTime: DateTime(2026, 10, 19, 10, index + 10).millisecondsSinceEpoch,
        overlapMilliseconds: const Duration(minutes: 1).inMilliseconds,
      ),
    );
    Future<bool?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                result = showTimeLogSaveConfirmation(
                  context: context,
                  start: DateTime(2026, 10, 19, 10),
                  end: DateTime(2026, 10, 19, 11),
                  overlaps: overlaps,
                  isFuture: false,
                  isEditing: false,
                );
              },
              child: const Text('打开确认'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();

    expect(find.text('记录 0'), findsOneWidget);
    expect(find.text('记录 3'), findsOneWidget);
    expect(find.text('记录 4'), findsNothing);
    expect(find.text('另有 2 条重叠记录'), findsOneWidget);
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
