import 'package:countdown_todo/features/thirty_day_challenge/screens/new_challenge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('自定义挑战页展示重排后的编辑区并实时预览任务', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const NewChallengeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('把想做的事，\n变成一场挑战'), findsOneWidget);
    expect(find.text('浏览云端挑战库'), findsOneWidget);
    expect(find.text('任务清单'), findsOneWidget);
    expect(find.text('每行一项任务'), findsOneWidget);
    expect(find.text('任务预览'), findsOneWidget);
    expect(find.text('创建并开始挑战'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '我的阅读挑战');
    await tester.enterText(fields.at(1), '读十页书\n写下一个想法');
    await tester.pump();

    expect(find.text('2 项任务'), findsOneWidget);
    expect(find.text('读十页书'), findsOneWidget);
    expect(find.text('写下一个想法'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
