import 'package:countdown_todo/screens/screen_time_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('离开屏幕使用时间详情会取消延迟加载', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ScreenTimeDetailScreen(todayStats: [])),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
