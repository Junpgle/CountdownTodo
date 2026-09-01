import 'package:countdown_todo/features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import 'package:countdown_todo/features/thirty_day_challenge/screens/challenge_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('未开始时展示挑战中心首页，并提供经典挑战介绍入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const ChallengeCenterScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('挑战中心'), findsOneWidget);
    expect(find.text('下一场挑战，\n由你决定'), findsOneWidget);
    expect(find.text('探索挑战库'), findsWidgets);
    expect(find.text('30天找到全新自我'), findsOneWidget);
    expect(find.text('点击查看挑战介绍'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有进行中的挑战时展示当前挑战和进度', (tester) async {
    await ThirtyDayChallengeRepository.startNewChallenge(
      title: '我的阅读挑战',
      taskTitles: ['读十页书', '写下一个想法'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const ChallengeCenterScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('我的阅读挑战'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('继续挑战'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已有其他挑战时，经典挑战卡片仍打开原有介绍', (tester) async {
    await ThirtyDayChallengeRepository.startNewChallenge(
      title: '当前自定义挑战',
      taskTitles: ['完成一件小事'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const ChallengeCenterScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final classicTitle = find.text('30天找到全新自我');
    await tester.ensureVisible(classicTitle);
    await tester.tap(classicTitle);
    await tester.pumpAndSettle();

    expect(find.text('开始这场挑战'), findsOneWidget);
    expect(find.text('当前自定义挑战'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
