import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/time_log_screen.dart';
import 'package:countdown_todo/services/time_log_editor_save_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime(2025, 4, 3, 10);
final _end = DateTime(2025, 4, 3, 11);

Future<void> _openEditor(
  WidgetTester tester, {
  required Future<TimeLogEditorSaveResult> Function(TimeLogItem) onSave,
  TimeLogItem? existingLog,
  List<TimeLogItem>? timeLogs,
  Size surfaceSize = const Size(420, 900),
  double textScale = 1,
  ThemeData? theme,
}) async {
  addTearDown(() async {
    tester.view.viewInsets = const FakeViewPadding();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.binding.setSurfaceSize(surfaceSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-time-log-editor'),
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: false,
                  enableDrag: false,
                  builder: (_) => TimeLogEntrySheet(
                    initialStart: _start,
                    initialEnd: _end,
                    tags: const [],
                    timeLogs:
                        timeLogs ??
                        (existingLog == null ? const [] : [existingLog]),
                    pomodoros: const [],
                    existingLog: existingLog,
                    onSave: onSave,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-time-log-editor')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('未修改时点遮罩直接关闭，不显示退出确认', (tester) async {
    var saveCount = 0;
    await _openEditor(
      tester,
      onSave: (log) async {
        saveCount++;
        return const TimeLogEditorSaveResult.saved();
      },
    );

    await tester.tapAt(const Offset(210, 100));
    await tester.pumpAndSettle();

    expect(find.text('保留这条时间日志？'), findsNothing);
    expect(find.text('补录事件'), findsNothing);
    expect(saveCount, 0);
  });

  testWidgets('遮罩与关闭按钮共用退出选择，继续编辑保留内容', (tester) async {
    var saveCount = 0;
    await _openEditor(
      tester,
      onSave: (log) async {
        saveCount++;
        return const TimeLogEditorSaveResult.saved();
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey('time-log-title')),
      '修改中的记录',
    );

    await tester.tapAt(const Offset(210, 100));
    await tester.pumpAndSettle();
    expect(find.text('保留这条时间日志？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('保留这条时间日志？'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('time-log-title')))
          .controller
          ?.text,
      '修改中的记录',
    );

    await tester.tap(find.byTooltip('关闭补录'));
    await tester.pumpAndSettle();
    expect(find.text('保留这条时间日志？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();

    expect(find.text('补录事件'), findsNothing);
    expect(saveCount, 0);
  });

  testWidgets('字段恢复到初始值后不再拦截退出', (tester) async {
    var saveCount = 0;
    await _openEditor(
      tester,
      onSave: (log) async {
        saveCount++;
        return const TimeLogEditorSaveResult.saved();
      },
    );
    final titleField = find.byKey(const ValueKey('time-log-title'));
    await tester.enterText(titleField, '临时标题');
    await tester.enterText(titleField, '');
    await tester.tap(find.byTooltip('关闭补录'));
    await tester.pumpAndSettle();

    expect(find.text('保留这条时间日志？'), findsNothing);
    expect(find.text('补录事件'), findsNothing);
    expect(saveCount, 0);
  });

  testWidgets('系统返回与下拉关闭都进入同一退出保护', (tester) async {
    await _openEditor(
      tester,
      onSave: (log) async => const TimeLogEditorSaveResult.saved(),
    );
    await tester.enterText(
      find.byKey(const ValueKey('time-log-title')),
      '待处理草稿',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await Navigator.of(
      tester.element(find.byKey(const ValueKey('time-log-title'))),
    ).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('保留这条时间日志？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('time-log-dismiss-handle')),
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();
    expect(find.text('保留这条时间日志？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
  });

  testWidgets('320px、大字号、深色键盘、横屏与桌面布局无溢出', (tester) async {
    await _openEditor(
      tester,
      surfaceSize: const Size(320, 640),
      textScale: 1.35,
      theme: ThemeData.dark(useMaterial3: true),
      onSave: (log) async => const TimeLogEditorSaveResult.saved(),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('time-log-title')),
      '窄屏大字草稿',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭补录'));
    await tester.pumpAndSettle();
    expect(find.text('保留这条时间日志？'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('重叠确认返回修改后继续保留表单输入', (tester) async {
    var saveCount = 0;
    final overlap = TimeLogItem(
      id: 'overlap-log',
      title: '已有日志',
      startTime: _start.millisecondsSinceEpoch,
      endTime: _end.millisecondsSinceEpoch,
    );
    await _openEditor(
      tester,
      timeLogs: [overlap],
      onSave: (log) async {
        saveCount++;
        return const TimeLogEditorSaveResult.saved();
      },
    );
    await tester.enterText(find.byKey(const ValueKey('time-log-title')), '新补录');
    await tester.tap(find.text('保存记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('以下记录与本次补录重叠'), findsOneWidget);

    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(find.textContaining('以下记录与本次补录重叠'), findsNothing);
    expect(find.text('补录事件'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('time-log-title')))
          .controller
          ?.text,
      '新补录',
    );
    expect(saveCount, 0);
  });

  testWidgets('保存失败保留输入，重试复用同一 UUID', (tester) async {
    var saveCount = 0;
    final attemptedIds = <String>[];
    await _openEditor(
      tester,
      onSave: (log) async {
        saveCount++;
        attemptedIds.add(log.id);
        return saveCount == 1
            ? TimeLogEditorSaveResult.failed(StateError('write failed'))
            : const TimeLogEditorSaveResult.saved();
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey('time-log-title')),
      '保留在表单里的标题',
    );

    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，输入已保留。请检查后重试。'), findsOneWidget);
    expect(find.text('补录事件'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('time-log-title')))
          .controller
          ?.text,
      '保留在表单里的标题',
    );

    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
    expect(saveCount, 2);
    expect(attemptedIds, hasLength(2));
    expect(attemptedIds[0], attemptedIds[1]);
    expect(find.text('补录事件'), findsNothing);
  });

  testWidgets('编辑保存保留原 UUID、创建时间和扩展字段', (tester) async {
    final existing = TimeLogItem(
      id: 'existing-log',
      title: '旧标题',
      tagUuids: const ['first-tag', 'second-tag'],
      startTime: _start.millisecondsSinceEpoch,
      endTime: _end.millisecondsSinceEpoch,
      remark: '原备注',
      version: 4,
      createdAt: 1_700_000_000_000,
      deviceId: 'device-a',
      teamUuid: 'team-a',
    );
    TimeLogItem? savedLog;
    await _openEditor(
      tester,
      existingLog: existing,
      onSave: (log) async {
        savedLog = log;
        return const TimeLogEditorSaveResult.saved();
      },
    );
    await tester.enterText(find.byKey(const ValueKey('time-log-title')), '新标题');
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();

    expect(savedLog, isNotNull);
    expect(savedLog!.id, existing.id);
    expect(savedLog!.version, existing.version + 1);
    expect(savedLog!.createdAt, existing.createdAt);
    expect(savedLog!.tagUuids, existing.tagUuids);
    expect(savedLog!.remark, existing.remark);
    expect(savedLog!.deviceId, existing.deviceId);
    expect(savedLog!.teamUuid, existing.teamUuid);
  });

  testWidgets('保存中阻止重复提交和离开', (tester) async {
    final saveResult = Completer<TimeLogEditorSaveResult>();
    var saveCount = 0;
    await _openEditor(
      tester,
      onSave: (log) {
        saveCount++;
        return saveResult.future;
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey('time-log-title')),
      '正在保存',
    );
    await tester.tap(find.text('保存记录'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);
    expect(saveCount, 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('保留这条时间日志？'), findsNothing);
    expect(find.text('补录事件'), findsOneWidget);

    saveResult.complete(const TimeLogEditorSaveResult.saved());
    await tester.pumpAndSettle();
    expect(find.text('补录事件'), findsNothing);
  });
}
