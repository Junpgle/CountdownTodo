import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/models/habit_progress.dart';
import 'package:countdown_todo/features/habits/services/habit_celebration_service.dart';
import 'package:countdown_todo/features/habits/services/habit_stamp_animation_queue.dart';
import 'package:countdown_todo/features/habits/widgets/habit_card.dart';
import 'package:countdown_todo/features/habits/widgets/habit_stamp_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final goal = HabitGoal(
    uuid: 'visible-stamp-goal',
    name: '晨间阅读',
    icon: '📖',
    sourceType: HabitSourceType.quantityCheckIn,
  );
  final rule = HabitGoalRuleRevision(
    habitUuid: goal.uuid,
    targetValue: 1,
    unit: '次',
  );

  late Duration previousVisibilityInterval;
  setUp(() async {
    previousVisibilityInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    HabitStampAnimationQueue.clearForTesting();
    SharedPreferences.setMockInitialValues({});
    await HabitCelebrationService.ensureInitialized();
    await HabitCelebrationService.setHapticsEnabled(false);
  });

  tearDown(() {
    HabitStampAnimationQueue.clearForTesting();
    VisibilityDetectorController.instance.updateInterval =
        previousVisibilityInterval;
  });

  testWidgets('hidden-tab completion waits until the card is visible', (
    tester,
  ) async {
    var hidden = false;
    var met = false;
    Widget buildHarness() => MaterialApp(
      home: Scaffold(
        body: Offstage(
          offstage: hidden,
          child: TickerMode(
            enabled: !hidden,
            child: _buildCard(goal, rule, met: met),
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildHarness());
    await tester.pump();

    hidden = true;
    met = true;
    await tester.pumpWidget(buildHarness());
    await tester.pump();
    expect(_stamp(tester).animate, isFalse);

    hidden = false;
    await tester.pumpWidget(buildHarness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();

    expect(_stamp(tester).animate, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('offscreen completion waits until scrolling reaches the card', (
    tester,
  ) async {
    final scrollController = ScrollController();
    var met = false;
    var visibleFraction = 0.0;
    Widget buildHarness() => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            children: [
              const SizedBox(height: 900),
              VisibilityDetector(
                key: const ValueKey('stamp-visibility-probe'),
                onVisibilityChanged: (info) {
                  visibleFraction = info.visibleFraction;
                },
                child: _buildCard(goal, rule, met: met),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildHarness());
    await tester.pump();

    met = true;
    await tester.pumpWidget(buildHarness());
    await tester.pump();
    expect(_stamp(tester).animate, isFalse);

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();

    expect(visibleFraction, greaterThan(0.2));
    expect(_stamp(tester).animate, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    scrollController.dispose();
  });

  testWidgets(
    'visible focus copy consumes a hidden home completion only once',
    (tester) async {
      final focusScrollController = ScrollController();
      var homeMet = false;
      var showHomeCard = false;
      var focusVisibleFraction = 0.0;

      Widget buildHarness() => MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              SingleChildScrollView(
                controller: focusScrollController,
                child: Column(
                  children: [
                    const SizedBox(height: 900),
                    VisibilityDetector(
                      key: const ValueKey('focus-stamp-probe'),
                      onVisibilityChanged: (info) {
                        focusVisibleFraction = info.visibleFraction;
                      },
                      child: _buildCard(
                        goal,
                        rule,
                        met: true,
                        key: const ValueKey('focus-stamp-copy'),
                      ),
                    ),
                  ],
                ),
              ),
              Offstage(
                offstage: !showHomeCard,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 650,
                    child: TickerMode(
                      enabled: showHomeCard,
                      child: _buildCard(
                        goal,
                        rule,
                        met: homeMet,
                        key: const ValueKey('home-stamp-copy'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(buildHarness());
      await tester.pump();

      homeMet = true;
      await tester.pumpWidget(buildHarness());
      await tester.pump();
      expect(
        HabitStampAnimationQueue.hasPending(
          habitUuid: goal.uuid,
          logicalDate: DateTime(2026, 10, 22),
        ),
        isTrue,
      );
      expect(_stampFor(tester, 'home-stamp-copy').animate, isFalse);
      expect(_stampFor(tester, 'focus-stamp-copy').animate, isFalse);

      focusScrollController.jumpTo(
        focusScrollController.position.maxScrollExtent,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();

      expect(focusVisibleFraction, greaterThan(0.2));
      expect(
        HabitStampAnimationQueue.hasPending(
          habitUuid: goal.uuid,
          logicalDate: DateTime(2026, 10, 22),
        ),
        isFalse,
      );
      expect(_stampFor(tester, 'focus-stamp-copy').animate, isTrue);
      expect(_stampFor(tester, 'home-stamp-copy').animate, isFalse);

      await tester.pump(const Duration(milliseconds: 600));
      showHomeCard = true;
      await tester.pumpWidget(buildHarness());
      await tester.pump();

      expect(_stampFor(tester, 'home-stamp-copy').animate, isFalse);
      expect(_stampFor(tester, 'focus-stamp-copy').animate, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      focusScrollController.dispose();
    },
  );

  testWidgets('visible completion still plays the stamp immediately', (
    tester,
  ) async {
    var met = false;
    Widget buildHarness() => MaterialApp(
      home: Scaffold(body: _buildCard(goal, rule, met: met)),
    );

    await tester.pumpWidget(buildHarness());
    await tester.pump();

    met = true;
    await tester.pumpWidget(buildHarness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(_stamp(tester).animate, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'card reused for a different met habit does not trigger stamp animation',
    (tester) async {
      final goal2 = HabitGoal(
        uuid: 'different-met-goal',
        name: '夜间冥想',
        icon: '🧘',
        sourceType: HabitSourceType.quantityCheckIn,
      );
      final rule2 = HabitGoalRuleRevision(
        habitUuid: goal2.uuid,
        targetValue: 1,
        unit: '次',
      );

      // Card initially renders goal1 (in progress)
      Widget buildHarness(
        HabitGoal currentGoal,
        HabitGoalRuleRevision currentRule,
        bool met,
      ) => MaterialApp(
        home: Scaffold(
          body: _buildCard(
            currentGoal,
            currentRule,
            met: met,
            key: const ValueKey('reusable-card-slot'),
          ),
        ),
      );

      await tester.pumpWidget(buildHarness(goal, rule, false));
      await tester.pump();
      expect(find.byType(HabitStampBadge), findsNothing);

      // Card slot is re-rendered with goal2 which is already met
      await tester.pumpWidget(buildHarness(goal2, rule2, true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Must render static stamp watermark without animate: true
      expect(_stamp(tester).animate, isFalse);
      expect(
        HabitStampAnimationQueue.hasPending(
          habitUuid: goal2.uuid,
          logicalDate: DateTime(2026, 10, 22),
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'card in ListView cache extent below screen does not claim stamp until scrolled into viewport',
    (tester) async {
      final scrollController = ScrollController();
      HabitStampAnimationQueue.request(
        habitUuid: goal.uuid,
        logicalDate: DateTime(2026, 10, 22),
      );

      Widget buildHarness() => MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: scrollController,
            itemCount: 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                // Takes up full screen height
                return const SizedBox(height: 1200);
              }
              return _buildCard(goal, rule, met: true);
            },
          ),
        ),
      );

      await tester.pumpWidget(buildHarness());
      await tester.pump();

      // Card is offscreen below viewport - stamp request must remain pending
      expect(
        HabitStampAnimationQueue.hasPending(
          habitUuid: goal.uuid,
          logicalDate: DateTime(2026, 10, 22),
        ),
        isTrue,
      );

      // Scroll card into view
      scrollController.jumpTo(1150);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();

      // Now card is visible, stamp animation should claim and animate
      expect(
        HabitStampAnimationQueue.hasPending(
          habitUuid: goal.uuid,
          logicalDate: DateTime(2026, 10, 22),
        ),
        isFalse,
      );
      expect(_stamp(tester).animate, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      scrollController.dispose();
    },
  );
}

HabitCard _buildCard(
  HabitGoal goal,
  HabitGoalRuleRevision rule, {
  required bool met,
  Key? key,
}) {
  final progress = HabitProgress(
    period: DateTime(2026, 10, 22),
    currentValue: met ? 1 : 0,
    targetValue: 1,
    completionRatio: met ? 1 : 0,
    hasRecord: met,
    goalMet: met,
    isPlanned: true,
    isFinished: false,
  );
  return HabitCard(
    key: key ?? const ValueKey('stamp-visibility-card'),
    goal: goal,
    rule: rule,
    dayProgress: HabitDayProgress(
      habit: goal,
      logicalDate: DateTime(2026, 10, 22),
      status: progress.dayStatus,
      progress: progress,
    ),
    onChanged: _noop,
  );
}

HabitStampBadge _stamp(WidgetTester tester) => tester.widget<HabitStampBadge>(
  find.byType(HabitStampBadge, skipOffstage: false),
);

HabitStampBadge _stampFor(WidgetTester tester, String key) =>
    tester.widget<HabitStampBadge>(_stampFinderFor(tester, key));

Finder _stampFinderFor(WidgetTester tester, String key) => find.descendant(
  of: find.byKey(ValueKey(key), skipOffstage: false),
  matching: find.byType(HabitStampBadge, skipOffstage: false),
);

void _noop() {}
