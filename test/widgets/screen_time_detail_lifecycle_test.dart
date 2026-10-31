import 'package:countdown_todo/screens/screen_time_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('离开屏幕使用时间详情会取消延迟加载', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ScreenTimeDetailScreen(todayStats: [])),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('屏幕时间详情内网格与列表内边距为 zero，避免产生多余空白', (tester) async {
    const dummyStats = [
      {
        'app_name': '微信',
        'device_name': 'Mac',
        'duration': 1800,
        'category': '社交通讯',
      },
      {
        'app_name': 'Xcode',
        'device_name': 'Mac',
        'duration': 1200,
        'category': '学习办公',
      },
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(top: 88, bottom: 90),
            viewPadding: EdgeInsets.only(top: 88, bottom: 90),
          ),
          child: ScreenTimeDetailScreen(todayStats: dummyStats),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    final gridViews = tester.widgetList<GridView>(find.byType(GridView));
    expect(gridViews, isNotEmpty);
    for (final grid in gridViews) {
      expect(grid.padding, equals(EdgeInsets.zero));
    }

    final listViews = tester.widgetList<ListView>(find.byType(ListView));
    expect(listViews, isNotEmpty);
    for (final list in listViews) {
      expect(list.padding, equals(EdgeInsets.zero));
    }
  });
}
