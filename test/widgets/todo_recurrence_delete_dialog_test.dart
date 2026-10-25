import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_recurrence_delete_service.dart';
import 'package:countdown_todo/widgets/todo_recurrence_delete_dialog.dart';
import 'package:countdown_todo/widgets/todo_group_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

const _fontFamily = 'Round26Preview';
const _cjkFontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
const _flutterRootFallback = '/Users/junpgle/develop/flutter';
final _hasCjkFont = Platform.isMacOS && File(_cjkFontPath).existsSync();
final _iconFontPath =
    '${Platform.environment['FLUTTER_ROOT'] ?? _flutterRootFallback}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var fontsLoaded = false;

  Future<void> loadPreviewFonts() async {
    if (fontsLoaded) return;
    if (_hasCjkFont) {
      final font = FontLoader(_fontFamily)
        ..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(await File(_cjkFontPath).readAsBytes()),
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
    fontsLoaded = true;
  }

  final selected = TodoItem(
    id: '00000000-0000-4000-8000-000000000026',
    title: '每周整理资料',
    recurrence: RecurrenceType.weekly,
    recurrenceSeriesId: '00000000-0000-4000-8000-000000000026',
    createdDate: DateTime(2026, 10, 20, 9).millisecondsSinceEpoch,
  );
  final todos = [
    TodoItem(
      id: '00000000-0000-4000-8000-000000000019',
      title: selected.title,
      recurrenceSeriesId: selected.recurrenceSeriesId,
      isDone: true,
      createdDate: DateTime(2026, 10, 19, 9).millisecondsSinceEpoch,
    ),
    selected,
    TodoItem(
      id: '00000000-0000-4000-8000-000000000021',
      title: selected.title,
      recurrenceSeriesId: selected.recurrenceSeriesId,
      isSkipped: true,
      createdDate: DateTime(2026, 10, 21, 9).millisecondsSinceEpoch,
    ),
  ];

  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xff6750a4),
          useMaterial3: true,
          fontFamily: _hasCjkFont ? _fontFamily : null,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showTodoRecurrenceDeleteDialog(
                  context: context,
                  todo: selected,
                  todos: todos,
                ),
                child: const Text('打开删除范围'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开删除范围'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await loadPreviewFonts();
  });

  testWidgets('范围选择展示期数和状态并二次确认整个系列', (tester) async {
    await openDialog(tester);

    expect(find.text('选择「每周整理资料」的删除范围'), findsOneWidget);
    expect(find.text('仅本期 · 1期'), findsOneWidget);
    expect(find.text('本期及以后 · 2期'), findsOneWidget);
    expect(find.text('整个系列 · 3期'), findsOneWidget);
    expect(find.text('1期已完成 · 1期已跳过'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('confirm_recurrence_delete')),
      findsOneWidget,
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/recurring_todo_delete_scope_phone.png'),
    );

    await tester.tap(find.byKey(const ValueKey('recurrence_delete_series')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('移入整个重复系列？'), findsOneWidget);
    expect(find.textContaining('3 期'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('confirm_delete_recurrence_series')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/recurring_todo_delete_series_confirm_phone.png',
      ),
    );
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
  });

  testWidgets('默认仅本期可直接确认，取消保持数据不变', (tester) async {
    TodoRecurrenceDeleteScope? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showTodoRecurrenceDeleteDialog(
                  context: context,
                  todo: selected,
                  todos: todos,
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
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(todos.every((todo) => !todo.isDeleted), isTrue);
  });

  testWidgets('文件夹滑动重复待办委托范围处理而不显示单条确认', (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    var deleteCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodoGroupWidget(
              group: TodoGroup(
                id: 'recurrence-delete-folder',
                name: '工作',
                isExpanded: true,
              ),
              groupTodos: [selected],
              isLight: true,
              teamRoles: const {},
              onToggle: () {},
              onTodoToggle: (_) {},
              onTodoDropped: (_) {},
              onDelete: () {},
              onTodoTap: (_) {},
              onTodoDelete: (_) async {
                deleteCalls++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dismissible = find.byKey(
      ValueKey('folder_todo_dismiss_${selected.id}'),
    );
    expect(dismissible, findsOneWidget);
    await tester.drag(dismissible, const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(deleteCalls, 1);
    expect(find.text('确认删除'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
