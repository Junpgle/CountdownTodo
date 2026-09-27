import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/fixed_schedule_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fixed schedule detail uses the shared detail layout',
      (tester) async {
    final item = FixedScheduleItem(
      id: 'schedule-1',
      title: '高等数学考试',
      date: '2026-09-02',
      startTime: DateTime(2026, 9, 2, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 9, 2, 11).millisecondsSinceEpoch,
      location: 'A101',
      remark: '携带计算器',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleDetailScreen(
          username: 'detail-test-user',
          item: item,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('固定日程详情'), findsOneWidget);
    expect(find.text('高等数学考试'), findsOneWidget);
    expect(find.byTooltip('编辑固定日程'), findsOneWidget);
    expect(find.text('2026年9月2日'), findsOneWidget);
    expect(find.text('A101'), findsOneWidget);
    expect(find.text('携带计算器'), findsOneWidget);
  });
}
