import 'dart:convert';

import 'package:countdown_todo/features/thirty_day_challenge/screens/cloud_challenge_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cacheKey = 'thirty_day_cloud_challenge_catalog_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      _cacheKey: jsonEncode({
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'catalog': {
          'format': 'countdowntodo.challenge_catalog',
          'version': 1,
          'updated_at': '2026-09-01',
          'challenges': [
            {
              'id': 'slow-life-7',
              'title': '7 天慢生活实验',
              'description': '把注意力带回真实生活。',
              'tags': ['7 天', '生活方式'],
              'tasks': ['不带手机散步'],
            },
            {
              'id': 'reading-spark-14',
              'title': '14 天阅读与思考',
              'description': '每天留出一块安静时间。',
              'tags': ['14 天', '阅读'],
              'tasks': ['读完一章书'],
            },
            {
              'id': 'reading-spark-7',
              'title': '7 天阅读与思考',
              'description': '用一周时间重新找回阅读节奏。',
              'tags': ['7 天', '阅读'],
              'tasks': ['读完一篇文章'],
            },
          ],
        },
      }),
    });
  });

  testWidgets('云端挑战库移除自定义 banner，并支持按标签筛选', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const CloudChallengePickerScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('创建自己的挑战'), findsNothing);
    expect(find.text('按标签筛选'), findsOneWidget);
    expect(find.text('每行一组标签，左右滑动查看更多，支持多选。'), findsOneWidget);
    expect(find.text('成长与行动'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsNWidgets(3),
    );
    expect(find.widgetWithText(FilterChip, '阅读'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '7 天'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '阅读'));
    await tester.pump();

    expect(find.text('14 天阅读与思考'), findsOneWidget);
    expect(find.text('7 天阅读与思考'), findsOneWidget);
    expect(find.text('7 天慢生活实验'), findsNothing);
    expect(find.text('2/3 份'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '14 天'));
    await tester.pump();

    expect(find.text('14 天阅读与思考'), findsOneWidget);
    expect(find.text('7 天阅读与思考'), findsNothing);
    await tester.ensureVisible(find.text('1/3 份'));
    expect(find.text('1/3 份'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '7 天'));
    await tester.pump();

    expect(find.text('14 天阅读与思考'), findsOneWidget);
    expect(find.text('7 天阅读与思考'), findsOneWidget);
    await tester.ensureVisible(find.text('2/3 份'));
    expect(find.text('2/3 份'), findsOneWidget);

    await tester.tap(find.text('清除标签'));
    await tester.pump();

    expect(find.text('14 天阅读与思考'), findsOneWidget);
    expect(find.text('7 天慢生活实验'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
