import 'dart:convert';

import 'package:countdown_todo/screens/quiz_screen.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpQuiz(WidgetTester tester, String username) async {
  SharedPreferences.setMockInitialValues({
    StorageService.keySettings: jsonEncode({
      'operators': ['+'],
      'min_num1': 1,
      'max_num1': 1,
      'min_num2': 1,
      'max_num2': 1,
      'max_result': 2,
    }),
  });

  await tester.pumpWidget(MaterialApp(home: QuizScreen(username: username)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('快速重复提交同一答案只前进一题', (tester) async {
    await _pumpQuiz(tester, 'quiz-double-submit');

    expect(find.text('1 + 1 = ?'), findsWidgets);
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('下一题'));
    await tester.tap(find.text('下一题'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('第 2 / 10 题'), findsOneWidget);
  });

  testWidgets('手动切换到下一题后不会被旧提交回调再次跳题', (tester) async {
    await _pumpQuiz(tester, 'quiz-manual-swipe');

    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('下一题'));
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 10 题'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 10 题'), findsOneWidget);
  });

  testWidgets('答题反馈期间退出会取消所有计时器', (tester) async {
    await _pumpQuiz(tester, 'quiz-dispose-pending-timers');

    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('下一题'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
