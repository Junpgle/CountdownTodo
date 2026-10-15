import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/time_estimation_repository.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/widgets/time_estimation_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.now();
  TimeEstimationResult result({String? username, int count = 3}) =>
      TimeEstimationResult(
        estimatedMinutes: 60,
        confidence: .45,
        reason: '参考相似已完成待办的累计专注',
        source: TimeEstimationSource.history,
        username: username,
        incompleteCount: 2,
        noActualCount: 1,
        samples: List.unmodifiable([
          for (var i = 0; i < count; i++)
            TimeEstimationSample(
              todoId: 'sample-$i',
              title: count > 3 ? '样本标题$i' : '复习高数',
              actualSeconds: [50, 60, 65][i % 3] * 60,
              endedAt: now.millisecondsSinceEpoch,
            ),
        ]),
      );
  Future<void> host(
    WidgetTester tester,
    TimeEstimationResult value, {
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
    bool glass = false,
    Brightness brightness = Brightness.light,
  }) async {
    await LiquidGlassEffectService.setEnabled(glass);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await LiquidGlassEffectService.setEnabled(false);
      GlassPerformanceMonitor.stop();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: Scaffold(body: TimeEstimationHint(result: value)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('time-estimation-evidence')));
    await tester.pumpAndSettle();
  }

  setUp(
    () => SharedPreferences.setMockInitialValues({
      'current_login_user': 'synthetic-estimate',
    }),
  );

  testWidgets('紧凑行不列历史，点击只读依据展示真实样本并能关闭', (tester) async {
    await host(tester, result());
    expect(find.text('预计专注用时 1小时'), findsOneWidget);
    expect(find.text('历史参考一般'), findsOneWidget);
    expect(find.text('复习高数'), findsNothing);
    await open(tester);
    expect(find.text('本次参考 3 个已完成待办'), findsOneWidget);
    expect(find.textContaining('50、60、65 分钟'), findsOneWidget);
    expect(find.textContaining('2 个已完成待办记录不完整'), findsOneWidget);
    expect(find.textContaining('不代表当前待办剩余时间'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('采纳'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('time-estimation-close')));
    await tester.pumpAndSettle();
    expect(find.text('估时依据'), findsNothing);
  });
  testWidgets('最多三组标题，不展示全部历史，数量仍是本次实际使用样本', (tester) async {
    await host(tester, result(count: 8));
    await open(tester);
    expect(find.text('本次参考 8 个已完成待办'), findsOneWidget);
    expect(find.text('样本标题2'), findsOneWidget);
    expect(find.text('样本标题3'), findsNothing);
    expect(find.textContaining('另有 5 组'), findsOneWidget);
  });
  for (final source in [
    TimeEstimationSource.heuristic,
    TimeEstimationSource.readFailure,
  ]) {
    testWidgets('$source依据不捏造相似样本', (tester) async {
      final reason = source == TimeEstimationSource.readFailure
          ? '历史记录读取失败'
          : '没有可靠的同类完成样本';
      await host(
        tester,
        TimeEstimationResult(
          estimatedMinutes: 30,
          confidence: .2,
          reason: reason,
          source: source,
        ),
      );
      await open(tester);
      expect(find.text(reason), findsOneWidget);
      expect(find.textContaining('本次参考'), findsNothing);
      expect(find.text('参考较少，可调整'), findsNWidgets(2));
    });
  }
  testWidgets('打开前或打开后切账号均不泄漏旧依据', (tester) async {
    await host(tester, result(username: 'synthetic-estimate'));
    await open(tester);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'another-user');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('复习高数'), findsNothing);
    expect(find.textContaining('账号已切换，请关闭'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('time-estimation-close')));
    await tester.pumpAndSettle();
    await open(tester);
    expect(find.text('估时依据'), findsNothing);
    expect(find.textContaining('账号已切换，请重新'), findsOneWidget);
  });
  for (final item in [
    (const Size(320, 640), 1.6, 220.0),
    (const Size(390, 844), 2.0, 0.0),
    (const Size(720, 360), 1.6, 130.0),
    (const Size(1280, 900), 2.0, 0.0),
  ]) {
    for (final glass in [false, true]) {
      testWidgets('依据可达无溢出 ${item.$1} 字体${item.$2} 玻璃$glass', (tester) async {
        await host(
          tester,
          result(count: 12),
          size: item.$1,
          scale: item.$2,
          keyboard: item.$3,
          glass: glass,
          brightness: glass ? Brightness.dark : Brightness.light,
        );
        await open(tester);
        expect(tester.takeException(), isNull);
        final close = find.byKey(const ValueKey('time-estimation-close'));
        expect(close.hitTestable(), findsOneWidget);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
