@TestOn('vm')
library;

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/screens/plan_editor_drafts_screen.dart';
import 'package:countdown_todo/services/plan_editor_draft_repository.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  late PlanAvailabilityFixture f;
  late PlanEditorDraftRepository repo;
  late TodoItem todo;
  late List<TodoPlanBlock> saves;
  const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
  final now = PlanAvailabilityFixture.now, day = PlanAvailabilityFixture.day;
  Finder key(String s) => find.byKey(ValueKey(s));
  PlanDraftFields fields({
    DateTime? start,
    String origin = 'timeline',
    int? offset,
  }) => PlanDraftFields(
    todoId: 'todo-target',
    title: '复习高数',
    start: (start ?? day.add(const Duration(hours: 9))).millisecondsSinceEpoch,
    end: (start ?? day.add(const Duration(hours: 9)))
        .add(const Duration(hours: 1))
        .millisecondsSinceEpoch,
    remark: '恢复完整备注',
    reminder: 15,
    pomodoro: 45,
    rounds: 3,
    origin: origin,
    offsetMinutes: offset ?? day.timeZoneOffset.inMinutes,
  );
  Future<PlanEditorDraft> seed({
    DateTime? start,
    String origin = 'timeline',
    int? offset,
  }) => repo.keep(
    identity,
    fields(start: start, origin: origin, offset: offset),
    targetId: 'reserved',
  );
  Future<void> action(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> keepMenu(WidgetTester tester) async {
    await action(tester, find.byTooltip('更多操作'));
    await action(tester, find.text('保留草稿'));
  }

  Future<void> edit(WidgetTester tester, String value) async {
    await tester.ensureVisible(key('plan-remark'));
    await tester.enterText(key('plan-remark'), value);
    await tester.pump();
  }

  Future<void> open(
    WidgetTester tester, {
    PlanEditorDraft? draft,
    bool sheet = false,
    bool list = false,
    bool occupied = false,
    bool failSave = false,
    Size? size,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size ?? const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        ),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () {
                if (list) {
                  openPlanEditorDrafts(c, identity.username, repository: repo);
                  return;
                }
                (sheet
                    ? showPlanBlockEditorSheet<void>
                    : showPlanBlockEditorPage<void>)(
                  context: c,
                  builder: (_) => PlanBlockEditorSheet(
                    fullPage: !sheet,
                    username: identity.username,
                    todos: [todo],
                    todoGroups: const [],
                    block: sheet
                        ? TodoPlanBlock(
                            id: 'existing',
                            todoId: todo.id,
                            startTime: day
                                .add(const Duration(hours: 9))
                                .millisecondsSinceEpoch,
                            endTime: day
                                .add(const Duration(hours: 10))
                                .millisecondsSinceEpoch,
                          )
                        : null,
                    startTime: day.add(const Duration(hours: 9)),
                    endTime: day.add(const Duration(hours: 10)),
                    initialTodoId: todo.id,
                    restoredDraft: draft,
                    draftRepository: repo,
                    clock: () => now,
                    onManageDrafts: () => openPlanEditorDrafts(
                      c,
                      identity.username,
                      repository: repo,
                    ),
                    saver:
                        (
                          b,
                          selection, {
                          expectedVersion,
                          expectedUpdatedAt,
                          newStatus,
                        }) async {
                          if (failSave) throw StateError('合成保存失败');
                          saves.add(b);
                          return b;
                        },
                    availabilityLoader: (q, {forceRefresh = false}) async =>
                        PlanAvailabilitySnapshot(
                          todo: todo,
                          coverage: '隔离应用内数据',
                          busy: occupied
                              ? [
                                  PlanBusyInterval(
                                    day.add(const Duration(hours: 8)),
                                    day.add(const Duration(hours: 12)),
                                    source: PlanBusySource.fixedSchedule,
                                  ),
                                ]
                              : [],
                        ),
                    onSaved: () {},
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await action(tester, find.text('打开'));
  }

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    repo = PlanEditorDraftRepository(database: f.db, clock: () => now);
    todo = TodoItem(id: 'todo-target', title: '复习高数');
    saves = [];
  });
  tearDown(() => f.dispose());

  testWidgets('untouched return has no prompt or persisted draft', (t) async {
    await open(t);
    await action(t, find.byType(BackButton));
    expect(find.text('保留这次规划？'), findsNothing);
    expect(find.text('打开'), findsOneWidget);
    expect(await repo.list(identity), isEmpty);
  });
  testWidgets('changed form continues editing and keeps note', (t) async {
    await open(t);
    await edit(t, '未保存');
    await action(t, find.byType(BackButton));
    expect(find.text('保留这次规划？'), findsOneWidget);
    await action(t, find.text('继续编辑'));
    expect(t.widget<TextField>(key('plan-remark')).controller!.text, '未保存');
    expect(await repo.list(identity), isEmpty);
  });
  testWidgets('reverting all manual changes avoids prompt', (t) async {
    await open(t);
    await edit(t, '临时');
    await edit(t, '');
    await action(t, find.byType(BackButton));
    expect(find.text('打开'), findsOneWidget);
  });
  testWidgets('discard new form exits without business or draft', (t) async {
    await open(t);
    await edit(t, '放弃');
    await action(t, find.byType(BackButton));
    await action(t, find.text('放弃修改'));
    expect(find.text('打开'), findsOneWidget);
    expect(saves, isEmpty);
    expect(await repo.list(identity), isEmpty);
  });
  testWidgets('keep and leave persists then same-todo hint restores note', (
    t,
  ) async {
    await open(t);
    await edit(t, '保留以后继续');
    await action(t, find.byType(BackButton));
    await action(t, find.text('保留草稿并离开'));
    expect(find.text('打开'), findsOneWidget);
    expect(await repo.list(identity), hasLength(1));
    await action(t, find.text('打开'));
    await action(t, find.text('此待办有未完成的本机草稿'));
    expect(t.widget<TextField>(key('plan-remark')).controller!.text, '保留以后继续');
    expect(key('plan-draft-restored'), findsOneWidget);
    expect(saves, isEmpty);
  });
  testWidgets(
    'explicit keep stays in editor and repeated keep updates same row',
    (t) async {
      await open(t);
      await edit(t, '第一版');
      await keepMenu(t);
      await edit(t, '第二版');
      await keepMenu(t);
      final rows = await repo.list(identity);
      expect(rows, hasLength(1));
      expect((await repo.read(identity, rows.single.id)).fields.remark, '第二版');
      expect(rows.single.revision, 2);
      expect(key('plan-block-editor-page'), findsOneWidget);
    },
  );
  testWidgets('unchanged restored draft returns and remains saved', (t) async {
    final d = await seed();
    await open(t, draft: d);
    await action(t, find.byType(BackButton));
    expect(find.text('保留这次规划？'), findsNothing);
    expect(await repo.list(identity), hasLength(1));
  });
  testWidgets('discard restored modifications deletes only that draft', (
    t,
  ) async {
    final d = await seed();
    await repo.keep(identity, fields(), targetId: 'another');
    await open(t, draft: d);
    await edit(t, '放弃改动');
    await action(t, find.byType(BackButton));
    expect(find.textContaining('也会删除这份'), findsOneWidget);
    await action(t, find.text('放弃修改'));
    expect(await repo.list(identity), hasLength(1));
  });
  testWidgets('capacity failure keeps unsaved inputs and offers management', (
    t,
  ) async {
    for (var i = 0; i < 5; i++) {
      await repo.keep(identity, fields(), targetId: 'target-$i');
    }
    await open(t);
    await edit(t, '不能丢失');
    await keepMenu(t);
    expect(find.textContaining('草稿已满5份'), findsOneWidget);
    expect(t.widget<TextField>(key('plan-remark')).controller!.text, '不能丢失');
    expect(await repo.list(identity), hasLength(5));
    expect(find.text('管理规划草稿'), findsOneWidget);
  });
  testWidgets('write failure never exits or displays successful keep', (
    t,
  ) async {
    await open(t);
    await edit(t, '失败还在');
    await f.db.execute('DROP TABLE local_plan_editor_drafts');
    await action(t, find.byType(BackButton));
    await action(t, find.text('保留草稿并离开'));
    expect(key('plan-block-editor-page'), findsOneWidget);
    expect(find.text('已保留到本机规划草稿'), findsNothing);
    expect(t.widget<TextField>(key('plan-remark')).controller!.text, '失败还在');
  });
  testWidgets('restored save uses reserved UUID clears draft and checks slot', (
    t,
  ) async {
    final d = await seed();
    await open(t, draft: d);
    await action(t, key('plan-save'));
    expect(saves.single.id, d.targetId);
    expect(saves.single.remark, '恢复完整备注');
    expect(saves.single.pomodoroMinutes, 45);
    expect(saves.single.pomodoroRounds, 3);
    expect(saves.single.reminderMinutes, 15);
    expect(await repo.list(identity), isEmpty);
  });
  for (final expired in [true, false]) {
    testWidgets(
      'restored ${expired ? 'expired' : 'occupied'} slot cannot save',
      (t) async {
        final d = await seed(
          start: expired ? now.subtract(const Duration(days: 1)) : null,
        );
        await open(t, draft: d, occupied: !expired);
        await action(t, key('plan-save'));
        expect(saves, isEmpty);
        expect(find.textContaining('草稿时段已过期'), findsOneWidget);
        expect(await repo.list(identity), hasLength(1));
        expect(key('plan-draft-date'), findsOneWidget);
      },
    );
  }
  testWidgets('timezone change requires explicit acknowledgement', (t) async {
    final d = await seed(offset: day.timeZoneOffset.inMinutes + 60);
    await open(t, draft: d);
    await action(t, key('plan-save'));
    expect(saves, isEmpty);
    await action(t, find.text('确认当前时区时间'));
    await action(t, key('plan-save'));
    expect(saves, hasLength(1));
  });
  testWidgets(
    'newer draft revision blocks old editor save and keeps new content',
    (t) async {
      final d = await seed();
      await open(t, draft: d);
      await repo.keep(identity, fields(), previous: d, targetId: d.targetId);
      await action(t, key('plan-save'));
      expect(saves, isEmpty);
      expect(find.text('草稿已更新，请重新读取后保存'), findsOneWidget);
      expect((await repo.read(identity, d.id)).revision, 2);
    },
  );
  testWidgets(
    'failed restore is explicit and cannot silently save empty form',
    (t) async {
      final d = await seed();
      await f.db.update('todos', {'is_completed': 1});
      await open(t, draft: d);
      expect(find.textContaining('草稿未能恢复'), findsOneWidget);
      expect(t.widget<FilledButton>(key('plan-save')).onPressed, isNull);
      expect(saves, isEmpty);
      expect(await repo.list(identity), hasLength(1));
    },
  );
  testWidgets('failed formal save retains draft and modified form', (t) async {
    final d = await seed();
    await open(t, draft: d, failSave: true);
    await edit(t, '需要重试');
    await action(t, key('plan-save'));
    expect(find.text('合成保存失败'), findsOneWidget);
    expect(await repo.list(identity), hasLength(1));
    expect(t.widget<TextField>(key('plan-remark')).controller!.text, '需要重试');
  });
  testWidgets('existing sheet prompts discard and offers no persistent keep', (
    t,
  ) async {
    await open(t, sheet: true);
    await edit(t, '修改旧规划');
    await action(t, find.byTooltip('关闭'));
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    expect(find.text('保留草稿并离开'), findsNothing);
    await action(t, find.text('继续编辑'));
    expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
  });
  testWidgets('draft list opens independent page and deletes explicitly', (
    t,
  ) async {
    await seed();
    await open(t, list: true);
    expect(find.text('仅保存在本机 · 1/5份'), findsOneWidget);
    await action(t, find.text('删除'));
    await action(t, find.text('删除草稿'));
    expect(find.textContaining('暂无规划草稿'), findsOneWidget);
  });
  for (final size in [const Size(320, 780), const Size(1280, 900)]) {
    testWidgets(
      'draft editor and exit dialog fit $size large font dark theme',
      (t) async {
        await open(t, size: size, scale: 1.8, brightness: Brightness.dark);
        await edit(t, '大字体');
        await action(t, find.byType(BackButton));
        expect(t.takeException(), isNull);
        await action(t, find.text('继续编辑'));
        expect(t.takeException(), isNull);
      },
    );
  }
}
