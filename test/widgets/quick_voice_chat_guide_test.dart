import 'package:countdown_todo/services/feature_tip_service.dart';
import 'package:countdown_todo/widgets/coach_mark_overlay.dart';
import 'package:countdown_todo/widgets/quick_voice_chat_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _GuidePage {
  final addKey = GlobalKey();
  late BuildContext context;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (pageContext) {
          context = pageContext;
          return Scaffold(
            body: const Center(child: Text('首页')),
            floatingActionButton: FloatingActionButton(
              key: addKey,
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    ),
  );

  Future<bool?> showVoice() =>
      QuickVoiceChatGuide.showIfNeeded(context: context, addButtonKey: addKey);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'voice chapter follows home and explains all three release actions',
    (tester) async {
      final page = _GuidePage();
      await page.pump(tester);
      final homeGuide = CoachMarkOverlay.show(
        context: page.context,
        steps: [
          CoachMarkStep(
            targetKey: page.addKey,
            title: '首页教程最后一步',
            description: '首页操作说明',
          ),
        ],
        onFinish: () {},
        onSkip: () {},
      );
      final sequence = homeGuide.then(
        (finished) async => finished ? await page.showVoice() : null,
      );
      await tester.pumpAndSettle();
      expect(find.text('首页教程最后一步'), findsOneWidget);
      expect(find.text('长按加号，开口说话'), findsNothing);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(find.text('首页教程最后一步'), findsNothing);
      expect(find.text('长按加号，开口说话'), findsOneWidget);
      expect(find.text('1 / 4'), findsOneWidget);
      expect(find.textContaining('松手后自动转写并发送给 AI'), findsOneWidget);
      expect(
        await FeatureTipService.hasTipBeenShown(QuickVoiceChatGuide.tipId),
        false,
      );

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('右上划，松手取消'), findsOneWidget);
      expect(find.textContaining('不会上传'), findsOneWidget);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('左上划，进入 AI 草稿'), findsOneWidget);
      expect(find.textContaining('不会自动发送'), findsOneWidget);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('使用前准备'), findsOneWidget);
      expect(find.textContaining('普通小米 MiMo API Key'), findsOneWidget);
      expect(find.textContaining('麦克风权限'), findsOneWidget);
      expect(find.text('4 / 4'), findsOneWidget);

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(await sequence, true);
      expect(
        await FeatureTipService.hasTipBeenShown(QuickVoiceChatGuide.tipId),
        true,
      );
      expect(await page.showVoice(), null);
      expect(find.text('长按加号，开口说话'), findsNothing);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'existing home completion still allows voice once, skipping persists',
    (tester) async {
      await FeatureTipService.markTipShown('coach_home_intro');
      final page = _GuidePage();
      await page.pump(tester);
      final shown = page.showVoice();
      await tester.pumpAndSettle();
      expect(find.text('长按加号，开口说话'), findsOneWidget);
      await tester.tap(find.text('跳过教程'));
      await tester.pumpAndSettle();
      expect(await shown, false);
      expect(await FeatureTipService.hasTipBeenShown('coach_home_intro'), true);
      expect(
        await FeatureTipService.hasTipBeenShown(QuickVoiceChatGuide.tipId),
        true,
      );
      expect(await page.showVoice(), null);
    },
  );

  testWidgets('skipping home does not start the following voice chapter', (
    tester,
  ) async {
    final page = _GuidePage();
    await page.pump(tester);
    final homeGuide = CoachMarkOverlay.show(
      context: page.context,
      steps: [
        CoachMarkStep(
          targetKey: page.addKey,
          title: '首页教程',
          description: '首页操作说明',
        ),
      ],
      onFinish: () {},
      onSkip: () {},
    );
    final sequence = homeGuide.then(
      (finished) async => finished ? await page.showVoice() : null,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过教程'));
    await tester.pumpAndSettle();
    expect(await sequence, null);
    expect(find.text('长按加号，开口说话'), findsNothing);
    expect(
      await FeatureTipService.hasTipBeenShown(QuickVoiceChatGuide.tipId),
      false,
    );
  });

  testWidgets('missing entry or disposed page leaves voice guide eligible', (
    tester,
  ) async {
    final page = _GuidePage();
    await page.pump(tester);
    expect(
      await QuickVoiceChatGuide.showIfNeeded(
        context: page.context,
        addButtonKey: GlobalKey(),
      ),
      null,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(await page.showVoice(), null);
    expect(
      await FeatureTipService.hasTipBeenShown(QuickVoiceChatGuide.tipId),
      false,
    );
  });

  testWidgets('small screen supports all steps with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final page = _GuidePage();
    await page.pump(tester);
    final guide = page.showVoice();
    await tester.pumpAndSettle();
    for (var step = 0; step < 4; step++) {
      expect(find.text('${step + 1} / 4'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.tap(find.text(step == 3 ? '完成' : '下一步'));
      await tester.pumpAndSettle();
    }
    expect(await guide, true);
    expect(tester.takeException(), null);
  });
}
