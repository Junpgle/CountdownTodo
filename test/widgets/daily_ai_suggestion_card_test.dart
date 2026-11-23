import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/daily_ai_suggestion_service.dart';
import 'package:countdown_todo/widgets/ai_water_border.dart';
import 'package:countdown_todo/widgets/daily_ai_suggestion_card.dart';

void main() {
  late Duration previousVisibilityInterval;

  setUp(() {
    previousVisibilityInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() {
    VisibilityDetectorController.instance.updateInterval =
        previousVisibilityInterval;
  });

  testWidgets('DailyAiSuggestionCard renders items without add-todo button', (
    tester,
  ) async {
    var refreshTapped = false;
    var dismissTapped = false;
    bool? toggledExpanded;
    TodoItem? openedTodo;

    final existingTodo = TodoItem(
      id: 'todo-1',
      title: '交实验报告',
      dueDate: DateTime(2026, 11, 15, 22, 0),
    );

    final snapshot = DailyAiSuggestionSnapshot(
      enabled: true,
      suggestion: DailyAiSuggestion(
        dateKey: '2026-11-15',
        summary: '今天建议先完成报告，再补齐复习进度。',
        generatedAtMs: 1,
        items: const [
          DailyAiSuggestionItem(
            title: '交实验报告',
            reason: '今晚22:00截止',
            priority: DailyAiSuggestionPriority.high,
            todoId: 'todo-1',
          ),
          DailyAiSuggestionItem(
            title: '整理错题本',
            reason: '下午空闲时段可做',
            priority: DailyAiSuggestionPriority.medium,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DailyAiSuggestionCard(
              snapshot: snapshot,
              isLight: false,
              todos: [existingTodo],
              onRefresh: () => refreshTapped = true,
              onToggleExpanded: (expanded) => toggledExpanded = expanded,
              onDismiss: () => dismissTapped = true,
              onOpenModelConfig: () {},
              onOpenTodo: (todo) => openedTodo = todo,
              onOpenAiChat: (_) {},
              onAskAiOnce: () {},
              onEnableDaily: () {},
              onKeepManualSection: () {},
              onDeclinePrompt: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('今日 AI 建议'), findsOneWidget);
    expect(find.text('2 项'), findsOneWidget);
    expect(find.text('今天建议先完成报告，再补齐复习进度。'), findsOneWidget);
    expect(find.text('交实验报告'), findsOneWidget);
    expect(find.text('整理错题本'), findsOneWidget);
    expect(find.text('+ 待办'), findsNothing);

    await tester.tap(find.text('交实验报告'));
    await tester.pump();
    expect(openedTodo?.id, 'todo-1');

    expect(find.byType(AiWaterRippleBorder), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('daily-ai-suggestion-refresh-btn')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('daily-ai-suggestion-expand-btn')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('daily-ai-suggestion-expand-btn')),
    );
    await tester.pump();
    expect(toggledExpanded, isFalse);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('daily-ai-suggestion-footer-refresh-btn'),
      ),
    );
    await tester.pump();
    expect(refreshTapped, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('daily-ai-suggestion-dismiss-btn')),
    );
    await tester.pump();
    expect(dismissTapped, isTrue);
  });

  testWidgets('DailyAiSuggestionCard renders first-open prompt actions', (
    tester,
  ) async {
    var askOnceTapped = false;
    var enableDailyTapped = false;
    var keepManualTapped = false;
    var declineTapped = false;

    const snapshot = DailyAiSuggestionSnapshot(
      enabled: false,
      showFirstOpenPrompt: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DailyAiSuggestionCard(
              snapshot: snapshot,
              isLight: false,
              todos: const [],
              onRefresh: () {},
              onToggleExpanded: (_) {},
              onDismiss: () {},
              onOpenModelConfig: () {},
              onOpenTodo: (_) {},
              onOpenAiChat: (_) {},
              onAskAiOnce: () => askOnceTapped = true,
              onEnableDaily: () => enableDailyTapped = true,
              onKeepManualSection: () => keepManualTapped = true,
              onDeclinePrompt: () => declineTapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('不知道做什么？问问AI'), findsOneWidget);
    expect(find.text('问问AI'), findsOneWidget);
    expect(find.text('以后每天打开都提供建议'), findsOneWidget);
    expect(find.text('保留板块，手动生成'), findsOneWidget);
    expect(find.text('我不需要'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('daily-ai-prompt-ask-once-btn')),
    );
    await tester.pump();
    expect(askOnceTapped, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('daily-ai-prompt-enable-daily-btn')),
    );
    await tester.pump();
    expect(enableDailyTapped, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('daily-ai-prompt-keep-manual-btn')),
    );
    await tester.pump();
    expect(keepManualTapped, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('daily-ai-prompt-decline-btn')),
    );
    await tester.pump();
    expect(declineTapped, isTrue);
  });

  testWidgets('DailyAiSuggestionCard renders manual-generate card', (
    tester,
  ) async {
    var generateTapped = false;
    var dismissTapped = false;

    const snapshot = DailyAiSuggestionSnapshot(
      enabled: false,
      showManualGenerateCard: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DailyAiSuggestionCard(
              snapshot: snapshot,
              isLight: false,
              todos: const [],
              onRefresh: () {},
              onToggleExpanded: (_) {},
              onDismiss: () => dismissTapped = true,
              onOpenModelConfig: () {},
              onOpenTodo: (_) {},
              onOpenAiChat: (_) {},
              onAskAiOnce: () => generateTapped = true,
              onEnableDaily: () {},
              onKeepManualSection: () {},
              onDeclinePrompt: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('生成今日建议'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('daily-ai-manual-generate-btn')),
    );
    await tester.pump();
    expect(generateTapped, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('daily-ai-suggestion-dismiss-btn')),
    );
    await tester.pump();
    expect(dismissTapped, isTrue);
  });
}
