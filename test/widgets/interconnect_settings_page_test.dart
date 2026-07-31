import 'package:countdown_todo/screens/settings/pages/interconnect_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('数据与互联页展示 MCP 介绍入口并可打开说明', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InterconnectSettingsPage(username: 'tester'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MCP 接入'), findsOneWidget);
    expect(find.text('让外部 AI 助手连接并管理个人待办'), findsOneWidget);

    await tester.tap(find.text('MCP 接入'));
    await tester.pumpAndSettle();

    expect(find.text('MCP（模型上下文协议）'), findsOneWidget);
    expect(find.text('开发者预览'), findsOneWidget);
    expect(find.text('首次建议只读'), findsOneWidget);
    expect(find.text('初期支持范围'), findsOneWidget);
  });

  testWidgets('数据与互联页展示重复待办合并入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InterconnectSettingsPage(username: 'tester'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('重复待办合并'), findsOneWidget);
    expect(find.text('手动选择并归并被拆开的循环系列'), findsOneWidget);
  });
}
