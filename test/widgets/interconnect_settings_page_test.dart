import 'package:CountDownTodo/screens/settings/pages/interconnect_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('数据与互联页展示循环待办合并入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InterconnectSettingsPage(username: 'tester'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('循环待办合并'), findsOneWidget);
    expect(find.text('手动选择并归并被拆开的循环系列'), findsOneWidget);
  });
}
