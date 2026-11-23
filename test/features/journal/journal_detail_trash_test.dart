import 'package:countdown_todo/features/journal/models/journal_entry.dart';
import 'package:countdown_todo/features/journal/screens/journal_detail_screen.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/features/journal/services/journal_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('详情删除确认取消不改数据，确认后返回可恢复结果', (tester) async {
    await initializeDateFormatting('zh_CN');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    expect(database, isNotNull);
    await tester.runAsync(() => DatabaseHelper.ensureJournalSchema(database!));
    addTearDown(() => database!.close());

    final storage = JournalStorage.forTesting(
      databaseLoader: (_) async => database!,
    );
    final entry = JournalEntry(
      id: 'detail-trash-entry',
      title: '海边日记',
      content: '风很轻。',
    );
    await tester.runAsync(
      () => storage.saveEntry(entry, const [], accountId: 'detail-trash'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: _JournalDetailLauncher(entry: entry, storage: storage),
      ),
    );
    await tester.tap(find.text('打开日记'));
    await _waitFor(tester, () => find.text('海边日记').evaluate().isNotEmpty);
    expect(find.text('海边日记'), findsOneWidget);

    await tester.tap(find.byTooltip('移至回收站'));
    await _waitFor(tester, () => find.text('移至回收站？').evaluate().isNotEmpty);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await _waitFor(tester, () => find.text('移至回收站？').evaluate().isEmpty);
    expect(
      await tester.runAsync(
        () => storage.loadEntry(entry.id, accountId: 'detail-trash'),
      ),
      isNotNull,
    );

    await tester.tap(find.byTooltip('移至回收站'));
    await _waitFor(tester, () => find.text('移至回收站？').evaluate().isNotEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '移至回收站'));
    await _waitFor(
      tester,
      () => find.text('movedToTrash').evaluate().isNotEmpty,
    );

    expect(find.text('movedToTrash'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => storage.loadEntry(entry.id, accountId: 'detail-trash'),
      ),
      isNull,
    );
    expect(
      (await tester.runAsync(
        () => storage.loadTrashEntries(accountId: 'detail-trash'),
      ))!.single.id,
      entry.id,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (ready()) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('详情页没有进入预期状态');
}

class _JournalDetailLauncher extends StatefulWidget {
  final JournalEntry entry;
  final JournalStorage storage;

  const _JournalDetailLauncher({required this.entry, required this.storage});

  @override
  State<_JournalDetailLauncher> createState() => _JournalDetailLauncherState();
}

class _JournalDetailLauncherState extends State<_JournalDetailLauncher> {
  JournalDetailResult? _result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(_result?.name ?? '未操作'),
        TextButton(
          onPressed: () async {
            final result = await Navigator.of(context)
                .push<JournalDetailResult>(
                  MaterialPageRoute(
                    builder: (_) => JournalDetailScreen(
                      accountId: 'detail-trash',
                      entry: widget.entry,
                      storage: widget.storage,
                    ),
                  ),
                );
            if (mounted) setState(() => _result = result);
          },
          child: const Text('打开日记'),
        ),
      ],
    ),
  );
}
