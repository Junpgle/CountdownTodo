import 'package:CountDownTodo/widgets/todo_recurrence_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseDate = DateTime(2026, 7, 15);

  List<TodoRecurrenceProgressNode> buildNodes() => [
        TodoRecurrenceProgressNode(
          date: baseDate.subtract(const Duration(days: 2)),
          state: TodoRecurrenceNodeState.completed,
          occurrenceId: 'completed',
        ),
        TodoRecurrenceProgressNode(
          date: baseDate.subtract(const Duration(days: 1)),
          state: TodoRecurrenceNodeState.overdue,
          occurrenceId: 'overdue',
        ),
        TodoRecurrenceProgressNode(
          date: baseDate,
          state: TodoRecurrenceNodeState.current,
          occurrenceId: 'current',
          isCurrent: true,
        ),
        TodoRecurrenceProgressNode(
          date: baseDate.add(const Duration(days: 1)),
          state: TodoRecurrenceNodeState.pending,
          occurrenceId: 'pending',
        ),
        TodoRecurrenceProgressNode(
          date: baseDate.add(const Duration(days: 2)),
          state: TodoRecurrenceNodeState.future,
        ),
        TodoRecurrenceProgressNode(
          date: baseDate.add(const Duration(days: 3)),
          state: TodoRecurrenceNodeState.neutral,
          label: '结束',
        ),
      ];

  Widget buildSubject({
    ValueChanged<TodoRecurrenceProgressNode>? onNodeTap,
    VoidCallback? onManage,
    int? totalCount = 4,
  }) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            child: TodoRecurrenceProgress(
              nodes: buildNodes(),
              completedCount: 1,
              totalCount: totalCount,
              overdueCount: 1,
              onNodeTap: onNodeTap,
              onManage: onManage,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders recurrence node states and compact summary',
      (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.textContaining('已完成 1/4 期'), findsOneWidget);

    await tester.tap(find.byKey(
      const ValueKey('recurrence_progress_toggle'),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text('已完成 1/4 期 · 1 逾期'), findsOneWidget);
  });

  testWidgets('node tap and timeline long press trigger callbacks',
      (tester) async {
    TodoRecurrenceProgressNode? tappedNode;
    var managed = false;
    final nodes = buildNodes();
    await tester.pumpWidget(buildSubject(
      onNodeTap: (node) => tappedNode = node,
      onManage: () => managed = true,
    ));

    await tester.tap(find.byKey(
      ValueKey('recurrence_node_${nodes[2].key}'),
    ));
    await tester.pump();
    expect(tappedNode?.occurrenceId, 'current');

    await tester.longPress(
      find.byKey(const ValueKey('todo_recurrence_progress')),
    );
    await tester.pump();
    expect(managed, isTrue);
  });

  testWidgets('many nodes use a horizontal scroll view on narrow layouts',
      (tester) async {
    final nodes = List.generate(
      12,
      (index) => TodoRecurrenceProgressNode(
        date: baseDate.add(Duration(days: index)),
        state: index == 0
            ? TodoRecurrenceNodeState.current
            : TodoRecurrenceNodeState.future,
        isCurrent: index == 0,
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Dismissible(
          key: const ValueKey('parent_dismissible'),
          direction: DismissDirection.endToStart,
          child: SizedBox(
            width: 240,
            child: TodoRecurrenceProgress(
              nodes: nodes,
              completedCount: 0,
              totalCount: 1,
            ),
          ),
        ),
      ),
    ));

    final scrollView = find.byType(SingleChildScrollView);
    expect(scrollView, findsOneWidget);
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    await tester.drag(scrollView, const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('open-ended recurrence omits a misleading total count',
      (tester) async {
    await tester.pumpWidget(buildSubject(totalCount: null));

    expect(find.textContaining('已完成 1 期'), findsOneWidget);
    expect(find.textContaining('已完成 1/'), findsNothing);
  });
}
