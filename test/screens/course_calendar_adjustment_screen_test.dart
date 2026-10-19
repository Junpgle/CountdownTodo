import 'dart:convert';

import 'package:countdown_todo/screens/course_calendar_adjustment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows transfer dates with short month-day labels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'course_calendar_adjustments_v1': jsonEncode({
        'transfers': [
          {'from_date': '2026-12-04', 'to_date': '2026-12-05', 'label': ''},
        ],
      }),
    });

    await tester.pumpWidget(
      const MaterialApp(home: CourseCalendarAdjustmentScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('12月4日 的课'), findsOneWidget);
    expect(find.text('调到 12月5日'), findsOneWidget);
  });
}
