import 'package:countdown_todo/screens/settings/server_choice_page.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('线路设置展示阿里云直连与 Cloudflare 中转的说明', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ServerChoicePage(
          initialServerChoice: ApiService.serverChoiceAliyunDirect,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阿里云直连（HTTP）'), findsOneWidget);
    expect(find.text('Cloudflare 中转（HTTPS）'), findsOneWidget);
    expect(find.textContaining('优点：链路更短'), findsOneWidget);
    expect(find.textContaining('客户端到中转入口使用 HTTPS'), findsOneWidget);
  });
}
