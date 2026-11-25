import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/screens/habit_edit_screen.dart';
import 'package:countdown_todo/features/habits/utils/habit_emoji_utils.dart';
import 'package:countdown_todo/features/habits/widgets/habit_drink_picker_sheet.dart';
import 'package:countdown_todo/features/habits/widgets/habit_emoji_picker_dialog.dart';
import 'package:countdown_todo/features/habits/widgets/habit_emoji_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/plan_availability_fixture.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('HabitEmojiUtils', () {
    test('isEmojiGrapheme 正确识别常见、BMP、按键、旗帜与 ZWJ 复合 Emoji', () {
      expect(HabitEmojiUtils.isEmojiGrapheme('🎯'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('🦊'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('⏰'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('⭐'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('✅'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('☕'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('1️⃣'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('#️⃣'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('🇨🇳'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('👨‍👩‍👧‍👦'), isTrue);
      expect(HabitEmojiUtils.isEmojiGrapheme('🏋🏽‍♀️'), isTrue);

      expect(HabitEmojiUtils.isEmojiGrapheme('a'), isFalse);
      expect(HabitEmojiUtils.isEmojiGrapheme('1'), isFalse);
      expect(HabitEmojiUtils.isEmojiGrapheme('跑'), isFalse);
    });

    test('extractSingleEmoji 支持任意单一 Emoji、追加覆盖与单符号，并拒绝多字纯文本', () {
      expect(HabitEmojiUtils.extractSingleEmoji('🦊'), '🦊');
      expect(HabitEmojiUtils.extractSingleEmoji('🎯🦊'), '🦊');
      expect(HabitEmojiUtils.extractSingleEmoji('👨‍👩‍👧‍👦'), '👨‍👩‍👧‍👦');
      expect(HabitEmojiUtils.extractSingleEmoji('🏋🏽‍♀️'), '🏋🏽‍♀️');
      expect(HabitEmojiUtils.extractSingleEmoji('🇨🇳'), '🇨🇳');
      expect(HabitEmojiUtils.extractSingleEmoji('1️⃣'), '1️⃣');
      expect(HabitEmojiUtils.extractSingleEmoji('∞'), '∞');

      expect(HabitEmojiUtils.extractSingleEmoji(''), isNull);
      expect(HabitEmojiUtils.extractSingleEmoji('   '), isNull);
      expect(HabitEmojiUtils.extractSingleEmoji('abc'), isNull);
      expect(HabitEmojiUtils.extractSingleEmoji('跑步'), isNull);
    });
  });

  group('HabitEmojiText', () {
    testWidgets('将 BMP、按键和 ZWJ Emoji 与汉字拆分为独立 WidgetSpan', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HabitEmojiText('⏰ 早起 1️⃣ 次 🏋🏽‍♀️')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RichText), findsWidgets);
      expect(find.text('⏰'), findsOneWidget);
      expect(find.text('1️⃣'), findsOneWidget);
      expect(find.text('🏋🏽‍♀️'), findsOneWidget);
    });
  });

  group('HabitEmojiPickerDialog 与 HabitEditScreen', () {
    testWidgets('HabitEditScreen 可通过自定义输入和复合 Emoji 自由修改图标', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: HabitEditScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('手动自定义'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('habit-edit-icon-picker')));
      await tester.pumpAndSettle();

      expect(find.byType(HabitEmojiPickerDialog), findsOneWidget);

      final customInput = find.byKey(
        const ValueKey('habit-emoji-custom-input'),
      );
      await tester.enterText(customInput, '🦊');
      await tester.pumpAndSettle();

      await tester.enterText(customInput, '🏋🏽‍♀️');
      await tester.pumpAndSettle();

      final confirmButton = find.byKey(const ValueKey('habit-emoji-confirm'));
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);

      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(find.byType(HabitEmojiPickerDialog), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('habit-edit-icon-picker')),
          matching: find.text('🏋🏽‍♀️'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('输入多字符非 Emoji 文本会报错并禁用确定按钮', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    HabitEmojiPickerDialog.show(context, initialIcon: '🎯'),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('habit-emoji-custom-input')),
        'abc',
      );
      await tester.pumpAndSettle();

      expect(find.text('请输入或粘贴 1 个 Emoji'), findsOneWidget);
      final confirmButton = find.byKey(const ValueKey('habit-emoji-confirm'));
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
    });

    testWidgets('支持切换分类挑选非预设 Emoji 且持久化最近使用记录', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? pickedIcon;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  pickedIcon = await HabitEmojiPickerDialog.show(
                    context,
                    initialIcon: '🎯',
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('最近'), findsNothing);

      final natureChip = find.text('自然动物');
      await tester.ensureVisible(natureChip);
      await tester.pumpAndSettle();
      await tester.tap(natureChip);
      await tester.pumpAndSettle();

      await tester.tap(find.text('🌱'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('habit-emoji-confirm')));
      await tester.pumpAndSettle();

      expect(pickedIcon, '🌱');

      // 再次打开时应出现「最近」分组并包含刚刚选择的 🌱
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('最近'), findsOneWidget);
      await tester.tap(find.text('最近'));
      await tester.pumpAndSettle();
      expect(find.text('🌱'), findsWidgets);
    });
  });

  group('HabitDrinkPickerSheet 自定义 Emoji 选择', () {
    late PlanAvailabilityFixture fixture;

    setUp(() async {
      fixture = PlanAvailabilityFixture();
      await fixture.initialize();
      debugDefaultTargetPlatformOverride = null;
    });

    tearDown(() => fixture.dispose());

    testWidgets('新增常用饮品可通过「全部 Emoji」或直接输入复合 Emoji 保存', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final goal = HabitGoal(
        uuid: 'habit-drink-test',
        name: '戒掉饮料',
        icon: '🥤',
        sourceType: HabitSourceType.recurringTodo,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitDrinkPickerSheet(
              goal: goal,
              rules: const [],
              logicalDate: DateTime(2026, 11, 25),
              username: PlanAvailabilityFixture.username,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();

      expect(find.text('新增常用饮品'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('drink-more-emoji-button')));
      await tester.pumpAndSettle();
      expect(find.byType(HabitEmojiPickerDialog), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('habit-emoji-custom-input')),
        '🧋',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('habit-emoji-custom-input')),
        '🏋🏽‍♀️',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('habit-emoji-confirm')));
      await tester.pumpAndSettle();

      final drinkIconField = tester.widget<TextField>(
        find.byKey(const ValueKey('drink-option-icon-input')),
      );
      expect(drinkIconField.controller?.text, '🏋🏽‍♀️');

      await tester.enterText(find.widgetWithText(TextField, '饮品名称'), '蛋白饮');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('🏋🏽‍♀️'), findsOneWidget);
      expect(find.text('蛋白饮'), findsOneWidget);
    });
  });
}
