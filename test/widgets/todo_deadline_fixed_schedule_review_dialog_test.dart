import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_deadline_fixed_schedule_review_service.dart';
import 'package:countdown_todo/widgets/todo_deadline_fixed_schedule_review_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewFontFamily = 'Round40DeadlineReviewPreview';
const _previewFontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
const _fallbackFlutterRoot = '/Users/junpgle/develop/flutter';
final _iconFontPath =
    '${Platform.environment['FLUTTER_ROOT'] ?? _fallbackFlutterRoot}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
final _hasPreviewFont = Platform.isMacOS && File(_previewFontPath).existsSync();

Future<void> _loadPreviewFonts() async {
  if (_hasPreviewFont) {
    final font = FontLoader(_previewFontFamily)
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_previewFontPath).readAsBytes()),
        ),
      );
    await font.load();
  }
  if (File(_iconFontPath).existsSync()) {
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_iconFontPath).readAsBytes()),
        ),
      );
    await iconFont.load();
  }
}

TodoDeadlineFixedScheduleReview _review() {
  final before = TodoItem(
    id: 'todo-review',
    title: '打印准考证',
    dueDate: DateTime(2026, 10, 26, 18),
  );
  final after = TodoItem.fromJson(before.toJson())
    ..dueDate = DateTime(2026, 10, 27, 18);
  final schedule = FixedScheduleItem(
    id: 'schedule-review',
    title: '线性代数考试',
    date: '2026-10-27',
    startTime: DateTime(2026, 10, 27, 9).millisecondsSinceEpoch,
    endTime: DateTime(2026, 10, 27, 11).millisecondsSinceEpoch,
    relatedTodoIds: ['todo-review'],
  );
  return TodoDeadlineFixedScheduleReviewService.build(
    changedTodos: [after],
    baselines: {'todo-review': before},
    schedules: [schedule],
    now: DateTime(2026, 10, 24),
  );
}

TodoDeadlineFixedScheduleReview _reviewWithGroups(int count) {
  final beforeTodos = List.generate(
    count,
    (index) => TodoItem(
      id: 'todo-review-$index',
      title: '准备事项 $index',
      dueDate: DateTime(2026, 10, 26, 18),
    ),
  );
  final afterTodos = beforeTodos
      .map(
        (todo) =>
            TodoItem.fromJson(todo.toJson())
              ..dueDate = DateTime(2026, 10, 27, 18),
      )
      .toList(growable: false);
  return TodoDeadlineFixedScheduleReviewService.build(
    changedTodos: afterTodos,
    baselines: {for (final todo in beforeTodos) todo.id: todo},
    schedules: List.generate(
      count,
      (index) => FixedScheduleItem(
        id: 'schedule-review-$index',
        title: '日程 $index',
        date: '2026-10-27',
        startTime: DateTime(2026, 10, 27, 9).millisecondsSinceEpoch,
        endTime: DateTime(2026, 10, 27, 11).millisecondsSinceEpoch,
        relatedTodoIds: ['todo-review-$index'],
      ),
    ),
    now: DateTime(2026, 10, 24),
  );
}

void main() {
  setUpAll(_loadPreviewFonts);

  testWidgets('复核弹窗显示期限前后、日程开始和非冲突说明', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: _hasPreviewFont ? _previewFontFamily : null,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.25)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showTodoDeadlineFixedScheduleReviewDialog(
                  context,
                  _review(),
                );
              },
              child: const Text('保存待办'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('保存待办'));
    await tester.pumpAndSettle();

    expect(find.text('关联固定日程复核'), findsOneWidget);
    expect(find.text('打印准考证'), findsOneWidget);
    expect(find.text('线性代数考试'), findsOneWidget);
    expect(find.textContaining('10月26日 18:00 前完成'), findsOneWidget);
    expect(find.textContaining('10月27日 18:00 前完成'), findsOneWidget);
    expect(find.text('日程开始 · 10月27日 09:00'), findsOneWidget);
    expect(find.textContaining('不代表时间冲突'), findsOneWidget);
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile(
        'goldens/round_40_deadline_review_phone_dark_large.png',
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('todo-deadline-review-confirm')),
    );
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回修改会取消确认，不影响屏幕输入', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showTodoDeadlineFixedScheduleReviewDialog(
                  context,
                  _review(),
                );
              },
              child: const Text('打开复核'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开复核'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo-deadline-review-return')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果超过五组时可展开查看余项', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showTodoDeadlineFixedScheduleReviewDialog(
                context,
                _reviewWithGroups(6),
              ),
              child: const Text('打开复核'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开复核'));
    await tester.pumpAndSettle();

    expect(find.text('日程 4'), findsOneWidget);
    expect(find.text('日程 5'), findsNothing);
    final showMore = find.text('查看其余 1 项');
    await tester.ensureVisible(showMore);
    await tester.tap(find.text('查看其余 1 项'));
    await tester.pumpAndSettle();
    expect(find.text('日程 5'), findsOneWidget);
    final collapse = find.text('收起');
    await tester.ensureVisible(collapse);
    await tester.tap(collapse);
    await tester.pumpAndSettle();
    expect(find.text('日程 5'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
