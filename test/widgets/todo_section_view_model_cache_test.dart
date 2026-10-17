import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/widgets/todo_section_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TodoCacheHarness extends StatefulWidget {
  const _TodoCacheHarness({
    required this.todos,
    this.updateParentOnTodosChanged = true,
  });

  final List<TodoItem> todos;
  final bool updateParentOnTodosChanged;

  @override
  State<_TodoCacheHarness> createState() => _TodoCacheHarnessState();
}

class _TodoCacheHarnessState extends State<_TodoCacheHarness> {
  late List<TodoItem> _todos = List<TodoItem>.from(widget.todos);

  void _handleTodosChanged(List<TodoItem> todos) {
    if (!widget.updateParentOnTodosChanged) return;
    setState(() => _todos = List<TodoItem>.from(todos));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              TextButton(
                key: const ValueKey('mutate-same-todo-list'),
                onPressed: () {
                  setState(() {
                    final todo = _todos.first;
                    todo.isDone = !todo.isDone;
                    todo.markAsChanged();
                  });
                },
                child: const Text('在原列表中修改'),
              ),
              TodoSectionWidget(
                key: const ValueKey('todo-section'),
                todos: _todos,
                username: 'cache-test',
                isLight: false,
                onTodosChanged: _handleTodosChanged,
                onRefreshRequested: () {},
                highlightedTodoIds: const {},
                remoteUpdateHighlightSignal: 0,
                todoGroups: const <TodoGroup>[],
                conflicts: const [],
                onGroupsChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
  });

  tearDown(ApiService.clearBaseUrlOverride);

  TodoItem todo({required bool isDone}) {
    final now = DateTime.now();
    return TodoItem(
      title: '缓存失效验证',
      isDone: isDone,
      createdDate: now.millisecondsSinceEpoch,
      dueDate: DateTime(now.year, now.month, now.day, 23, 59),
    );
  }

  testWidgets('parent mutation of the same list invalidates the view model', (
    tester,
  ) async {
    await tester.pumpWidget(_TodoCacheHarness(todos: [todo(isDone: false)]));
    await tester.pumpAndSettle();

    expect(find.text('今日 · 0/1 已完成'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mutate-same-todo-list')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('today_summary_card')));
    await tester.pumpAndSettle();

    expect(find.text('今日 · 1/1 已完成'), findsOneWidget);
  });

  testWidgets('local completion rebuild invalidates the cached view model', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TodoCacheHarness(
        todos: [todo(isDone: true)],
        updateParentOnTodosChanged: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('today_summary_card')));
    await tester.pumpAndSettle();
    expect(find.text('今日 · 1/1 已完成'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(find.text('今日 · 0/1 已完成'), findsOneWidget);
  });
}
