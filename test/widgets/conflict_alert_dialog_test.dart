import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/utils/time_utils.dart';
import 'package:countdown_todo/widgets/conflict_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('formats conflict timestamp ranges for display', (tester) async {
    final start = DateTime(2026, 12, 4, 9, 15);
    final end = DateTime(2026, 12, 4, 10, 30);
    final expectedRange =
        '${AppTimeFormats.format(start, 'MM-dd HH:mm')} ~ ${AppTimeFormats.clock(end)}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConflictAlertDialog(
            conflicts: [
              ConflictInfo(
                type: 'schedule_conflict',
                item: {
                  'content': '项目 A',
                  'start_time': start.toUtc().millisecondsSinceEpoch,
                  'end_time': end.toUtc().millisecondsSinceEpoch,
                },
                conflictWith: const {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('您的版本: 项目 A'), findsOneWidget);
    expect(find.text(expectedRange), findsOneWidget);
  });
}
